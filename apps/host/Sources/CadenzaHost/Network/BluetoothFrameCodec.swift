import Foundation

// Frames are a 4-byte big-endian length followed by the payload, split across characteristic values. The stream has no
// markers to resync on, so a lost fragment cannot be skipped: the length would swallow the next frames. Instead a
// frame that stops growing is treated as damaged, and the caller ends the link so the Remote reconnects cleanly.
final class BluetoothFrameCodec {
    static let maximumFrameBytes = 1_048_576
    // Seconds of silence inside a partly received frame. A healthy link delivers the next fragment within a few
    // connection events, so this only fires when the link or the Remote has stalled mid-frame.
    static let stalledFrameSeconds = 10.0
    static let defaultChunkBytes = 182
    static let minimumChunkBytes = 20

    private var buffer = Data()
    private var expectedLength: Int?
    private var lastProgress = 0.0
    private let now: () -> Double

    init(now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    private var hasPartialFrame: Bool { expectedLength != nil || !buffer.isEmpty }

    func append(_ chunk: Data) throws -> [Data] {
        let time = now()
        if hasPartialFrame, time - lastProgress > Self.stalledFrameSeconds {
            reset()
            throw CadenzaError.failure("invalid_command", "Bluetooth frame stalled before it was complete.")
        }
        guard chunk.count <= Self.maximumFrameBytes + 4 else {
            reset()
            throw CadenzaError.failure("invalid_command", "Bluetooth frame is too large.")
        }
        lastProgress = time
        buffer.append(chunk)
        var frames: [Data] = []
        while true {
            if expectedLength == nil, buffer.count >= 4 {
                let length = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
                guard length <= Self.maximumFrameBytes else {
                    reset()
                    throw CadenzaError.failure("invalid_command", "Bluetooth frame length is invalid.")
                }
                expectedLength = length
                buffer.removeFirst(4)
            }
            guard let expectedLength, buffer.count >= expectedLength else { return frames }
            frames.append(Data(buffer.prefix(expectedLength)))
            buffer.removeFirst(expectedLength)
            self.expectedLength = nil
        }
    }

    func reset() {
        buffer.removeAll(keepingCapacity: false)
        expectedLength = nil
    }

    static func chunks(for payload: Data, maximumChunkBytes: Int = defaultChunkBytes) throws -> [Data] {
        guard payload.count <= maximumFrameBytes else {
            throw CadenzaError.failure("invalid_command", "Bluetooth frame is too large.")
        }
        guard maximumChunkBytes >= minimumChunkBytes else {
            throw CadenzaError.failure("invalid_command", "Bluetooth packet size is invalid.")
        }
        var framed = Data()
        framed.append(UInt8((payload.count >> 24) & 0xFF))
        framed.append(UInt8((payload.count >> 16) & 0xFF))
        framed.append(UInt8((payload.count >> 8) & 0xFF))
        framed.append(UInt8(payload.count & 0xFF))
        framed.append(payload)
        return stride(from: 0, to: framed.count, by: maximumChunkBytes).map { offset in
            Data(framed[offset..<min(offset + maximumChunkBytes, framed.count)])
        }
    }
}
