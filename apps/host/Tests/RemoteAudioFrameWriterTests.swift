import Foundation
import Testing

@testable import CadenzaHost

struct RemoteAudioFrameWriterTests {
    final class FakeSocket: @unchecked Sendable {
        private let lock = NSLock()
        private var payloads: [Data] = []
        private var completions: [@Sendable () -> Void] = []

        var write: RemoteAudioFrameWriter.Write {
            { payload, onWritten in
                self.lock.withLock {
                    self.payloads.append(payload)
                    self.completions.append(onWritten)
                }
            }
        }

        var sent: [Data] {
            lock.withLock { payloads }
        }

        func accept(_ index: Int) {
            let completion = lock.withLock { completions[index] }
            completion()
        }
    }

    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: UInt64

        init(_ value: UInt64) {
            self.value = value
        }

        var now: UInt64 {
            get { lock.withLock { value } }
            set { lock.withLock { value = newValue } }
        }
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func increment() {
            lock.withLock { count += 1 }
        }

        var value: Int {
            lock.withLock { count }
        }
    }

    private static func frame(sequence: UInt32, playoutUs: UInt64) -> RemoteAudioWire.AudioFrame {
        RemoteAudioWire.AudioFrame(
            flag: .pureFullRange, channels: 2, bitDepth: .float32, sequenceNumber: sequence, hostCaptureTimeUs: 0,
            targetPlayoutHostUs: playoutUs, frameCount: 4, payload: Data(count: 4 * 2 * 4))
    }

    @Test func framesLeaveInOrderAndControlMessagesFollowThem() {
        let socket = FakeSocket()
        let clock = Clock(1_000_000)
        let writer = RemoteAudioFrameWriter(write: socket.write, now: { clock.now }, onDegraded: {})
        let first = Self.frame(sequence: 0, playoutUs: 1_100_000)
        let second = Self.frame(sequence: 1, playoutUs: 1_110_000)

        writer.send(first)
        writer.sendControl(Data([0x02, 0x00, 0x00, 0x00, 0x07]))
        writer.send(second)

        let sent = socket.sent
        #expect(sent.count == 3)
        #expect(sent[0] == RemoteAudioWire.encode(first))
        #expect(sent[1] == Data([0x02, 0x00, 0x00, 0x00, 0x07]))
        #expect(sent[2] == RemoteAudioWire.encode(second))
    }

    @Test func theSocketsAcceptanceGovernsTheInFlightCap() {
        let socket = FakeSocket()
        let clock = Clock(1_000_000)
        let writer = RemoteAudioFrameWriter(write: socket.write, now: { clock.now }, onDegraded: {})

        writer.send(Self.frame(sequence: 0, playoutUs: 1_100_000))
        writer.send(Self.frame(sequence: 1, playoutUs: 1_100_000))
        writer.send(Self.frame(sequence: 2, playoutUs: 1_100_000))
        #expect(socket.sent.count == 2)
        #expect(writer.statistics() == .init(droppedInFlight: 1, droppedLate: 0))

        socket.accept(0)
        writer.send(Self.frame(sequence: 3, playoutUs: 1_100_000))
        #expect(socket.sent.count == 3)
    }

    @Test func aFrameThatCannotArriveBeforePlayoutIsDroppedAsLate() {
        let socket = FakeSocket()
        let clock = Clock(1_000_000)
        let writer = RemoteAudioFrameWriter(write: socket.write, now: { clock.now }, onDegraded: {})

        writer.send(Self.frame(sequence: 0, playoutUs: 1_003_999))

        #expect(socket.sent.isEmpty)
        #expect(writer.statistics() == .init(droppedInFlight: 0, droppedLate: 1))
    }

    @Test func aClosedWriterSendsNothingAndCountsNothing() {
        let socket = FakeSocket()
        let clock = Clock(1_000_000)
        let writer = RemoteAudioFrameWriter(write: socket.write, now: { clock.now }, onDegraded: {})

        writer.close()
        writer.send(Self.frame(sequence: 0, playoutUs: 1_100_000))
        writer.sendControl(Data([0x02]))

        #expect(socket.sent.isEmpty)
        #expect(writer.statistics().dropped == 0)
    }

    @Test func dropsLeaveTheSixtySecondWindow() {
        let socket = FakeSocket()
        let clock = Clock(1_000_000)
        let writer = RemoteAudioFrameWriter(write: socket.write, now: { clock.now }, onDegraded: {})

        writer.send(Self.frame(sequence: 0, playoutUs: 1_000_000))
        #expect(writer.statistics().droppedLate == 1)

        clock.now += 61_000_000
        #expect(writer.statistics().dropped == 0)
    }

    @Test func aSustainedDropRateReportsDegradedOnceForTheStream() {
        let socket = FakeSocket()
        let clock = Clock(1_000_000)
        let degraded = Counter()
        let writer = RemoteAudioFrameWriter(write: socket.write, now: { clock.now }, onDegraded: degraded.increment)

        for second in 0..<6 {
            clock.now = 1_000_000 + UInt64(second) * 1_000_000
            for _ in 0..<30 {
                writer.send(Self.frame(sequence: 0, playoutUs: clock.now))
            }
        }

        #expect(degraded.value == 1)
        #expect(socket.sent.isEmpty)
    }
}
