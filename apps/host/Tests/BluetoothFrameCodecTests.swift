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
}
