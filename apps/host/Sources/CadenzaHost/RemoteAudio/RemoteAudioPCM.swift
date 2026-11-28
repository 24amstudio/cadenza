import Foundation

enum RemoteAudioPCM {
    static func littleEndian16(_ samples: [Float]) -> Data {
        var data = Data(count: samples.count * 2)
        data.withUnsafeMutableBytes { raw in
            for (index, sample) in samples.enumerated() {
                let value = Int16((clamped(sample) * 32_767).rounded())
                raw.storeBytes(of: value.littleEndian, toByteOffset: index * 2, as: Int16.self)
            }
        }
        return data
    }

    static func littleEndian24(_ samples: [Float]) -> Data {
        var data = Data(count: samples.count * 3)
        data.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            for (index, sample) in samples.enumerated() {
                let value = Int32((clamped(sample) * 8_388_607).rounded())
                let bits = UInt32(bitPattern: value)
                let base = index * 3
                raw[base] = UInt8(bits & 0xFF)
                raw[base + 1] = UInt8((bits >> 8) & 0xFF)
                raw[base + 2] = UInt8((bits >> 16) & 0xFF)
            }
        }
        return data
    }

    private static func clamped(_ sample: Float) -> Float {
        min(1, max(-1, sample))
    }
}
