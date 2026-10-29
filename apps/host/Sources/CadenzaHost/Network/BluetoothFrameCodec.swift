import Foundation

final class BluetoothFrameCodec {
    static let maximumFrameBytes = 1_048_576
    private var buffer = Data()
    private var expectedLength: Int?

    func append(_ chunk: Data) throws -> [Data] {
        guard chunk.count <= Self.maximumFrameBytes + 4 else {
            throw CadenzaError.failure("invalid_command", "Bluetooth frame is too large.")
        }
        buffer.append(chunk)
        var frames: [Data] = []
        while true {
            if expectedLength == nil, buffer.count >= 4 {
                let length = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
                guard length <= Self.maximumFrameBytes else {
                    buffer.removeAll(keepingCapacity: false)
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

    static func chunks(for payload: Data, maximumChunkBytes: Int = 182) throws -> [Data] {
        guard payload.count <= maximumFrameBytes else {
            throw CadenzaError.failure("invalid_command", "Bluetooth frame is too large.")
        }
        guard maximumChunkBytes >= 20 else {
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
