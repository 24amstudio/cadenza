import XCTest

@testable import CadenzaHost

final class BluetoothFrameCodecTests: XCTestCase {
    func testCodecReassemblesMultipleFramesAcrossChunks() throws {
        let first = Data("first".utf8)
        let second = Data(repeating: 7, count: 300)
        let bytes =
            try BluetoothFrameCodec.chunks(for: first, maximumChunkBytes: 20)
            + BluetoothFrameCodec.chunks(for: second, maximumChunkBytes: 20)
        let codec = BluetoothFrameCodec()
        var result: [Data] = []
        for chunk in bytes { result += try codec.append(chunk) }
        XCTAssertEqual(result, [first, second])
    }

    func testCodecRejectsOversizedPayload() {
        XCTAssertThrowsError(
            try BluetoothFrameCodec.chunks(
                for: Data(repeating: 1, count: BluetoothFrameCodec.maximumFrameBytes + 1)))
    }

    func testFramesMatchTheRemoteAndWebGoldenBytes() throws {
        // The Android and Web codec tests assert the same bytes: 4-byte big-endian length, then the payload.
        XCTAssertEqual(
            try BluetoothFrameCodec.chunks(for: Data("hello".utf8), maximumChunkBytes: 20),
            [Data([0, 0, 0, 5, 104, 101, 108, 108, 111])])
        XCTAssertEqual(
            try BluetoothFrameCodec.chunks(for: Data(count: 40), maximumChunkBytes: 20).map(\.count), [20, 20, 4])
    }

    func testFrameThatStopsGrowingIsDroppedInsteadOfSwallowingLaterFrames() throws {
        var clock = 0.0
        let codec = BluetoothFrameCodec(now: { clock })
        let lost = try BluetoothFrameCodec.chunks(for: Data(repeating: 1, count: 100), maximumChunkBytes: 20)
        // The Remote sent six fragments of the frame, and one never arrived. The codec waits for bytes that cannot come.
        for chunk in lost.prefix(3) { XCTAssertEqual(try codec.append(chunk), []) }
        clock += BluetoothFrameCodec.stalledFrameSeconds + 1
        let next = try BluetoothFrameCodec.chunks(for: Data("command".utf8))
        XCTAssertThrowsError(try codec.append(next[0]))
        // After the link restarts, the codec reads frames from a clean state.
        XCTAssertEqual(try codec.append(next[0]), [Data("command".utf8)])
    }

    func testSlowButSteadyFrameIsNotTreatedAsStalled() throws {
        var clock = 0.0
        let codec = BluetoothFrameCodec(now: { clock })
        let payload = Data(repeating: 9, count: 400)
        var result: [Data] = []
        for chunk in try BluetoothFrameCodec.chunks(for: payload, maximumChunkBytes: 20) {
            clock += BluetoothFrameCodec.stalledFrameSeconds - 1
            result += try codec.append(chunk)
        }
        XCTAssertEqual(result, [payload])
    }

    func testImplausibleLengthEndsTheLinkAndLeavesNoBufferedBytes() throws {
        let codec = BluetoothFrameCodec()
        XCTAssertThrowsError(try codec.append(Data([0xFF, 0xFF, 0xFF, 0xFF, 1, 2, 3])))
        XCTAssertEqual(try codec.append(BluetoothFrameCodec.chunks(for: Data("ok".utf8))[0]), [Data("ok".utf8)])
    }
}

final class BluetoothSendQueueTests: XCTestCase {
    private func chunks(_ bytes: Int) -> [Data] {
        try! BluetoothFrameCodec.chunks(for: Data(repeating: 1, count: bytes - 4), maximumChunkBytes: 100)
    }

    func testWindowRefusesFramesBeyondItsBoundAndReportsWhenToRetry() {
        var queue = BluetoothSendQueue()
        XCTAssertTrue(queue.enqueue(chunks(3_000), bulk: false, completion: { _ in }))
        // 3 000 queued: a second 3 000-byte frame would pass the window, so it is refused.
        XCTAssertFalse(queue.enqueue(chunks(3_000), bulk: false, completion: { _ in }))
        XCTAssertFalse(queue.takeDrainNotice())
        while queue.pendingBytes > BluetoothSendQueue.refillBytes { queue.didSendChunk() }
        XCTAssertTrue(queue.takeDrainNotice())
        XCTAssertFalse(queue.takeDrainNotice(), "The notice is delivered once per refusal.")
        XCTAssertTrue(queue.enqueue(chunks(3_000), bulk: false, completion: { _ in }))
    }

    func testOversizedFrameGetsAnEmptyQueueButNeverQueuesBehindOthers() {
        var queue = BluetoothSendQueue()
        XCTAssertTrue(queue.enqueue(chunks(200_000), bulk: false, completion: { _ in }))
        XCTAssertFalse(queue.enqueue(chunks(100), bulk: false, completion: { _ in }))
    }

    func testBulkFrameIsAdmittedOnlyIntoAnEmptyWindow() {
        var queue = BluetoothSendQueue()
        XCTAssertTrue(queue.enqueue(chunks(300), bulk: true, completion: { _ in }))
        // A bulk frame waits behind a frame that is still pending, so no artwork sits ahead of a heartbeat.
        XCTAssertFalse(queue.enqueue(chunks(300), bulk: true, completion: { _ in }))
        while !queue.isEmpty { queue.didSendChunk() }
        XCTAssertTrue(queue.enqueue(chunks(300), bulk: true, completion: { _ in }))
    }

    func testStateFrameStillQueuesBehindAPendingBulkFrame() {
        var queue = BluetoothSendQueue()
        XCTAssertTrue(queue.enqueue(chunks(300), bulk: true, completion: { _ in }))
        // The state frame is small and fits in the window, so the bulk policy does not hold it back.
        XCTAssertTrue(queue.enqueue(chunks(40), bulk: false, completion: { _ in }))
    }

    func testCompletionRunsOnceAfterTheLastChunkAndRemovalFailsTheRest() {
        var queue = BluetoothSendQueue()
        var completed = 0
        XCTAssertTrue(queue.enqueue(chunks(250), bulk: false, completion: { _ in completed += 1 }))
        XCTAssertTrue(queue.enqueue(chunks(10), bulk: false, completion: { _ in completed += 10 }))
        XCTAssertEqual(queue.nextChunk?.count, 100)
        queue.didSendChunk()
        queue.didSendChunk()
        XCTAssertEqual(completed, 0)
        queue.didSendChunk()
        XCTAssertEqual(completed, 1)
        let rest = queue.removeAll()
        XCTAssertEqual(rest.count, 1)
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.pendingBytes, 0)
    }
}
