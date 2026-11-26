import Foundation

/// The fields of an AC-3 syncframe that a receiver and its `dac3` box need. Only 48 kHz streams are produced by the
/// Host's encoder, so other sample-rate codes are rejected.
struct AC3SyncInfo: Equatable, Sendable {
    let frameBytes: Int
    let channels: Int
    let lfe: Bool
    let fscod: UInt8
    let bsid: UInt8
    let bsmod: UInt8
    let acmod: UInt8
    let bitRateCode: UInt8

    private static let bitRatesKbps = [
        32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 448, 512, 576, 640,
    ]
    private static let channelsByMode = [2, 1, 2, 3, 3, 4, 4, 5]

    /// Parses one syncframe header at the start of `bytes`. Returns nil when the sync word, sample rate, or bit rate is
    /// not one that the contract allows.
    init?(_ bytes: Data) {
        guard bytes.count >= 8, bytes[bytes.startIndex] == 0x0B, bytes[bytes.startIndex + 1] == 0x77 else { return nil }
        let base = bytes.startIndex
        let fscod = bytes[base + 4] >> 6
        let frameSizeCode = bytes[base + 4] & 0x3F
        guard fscod == 0, frameSizeCode < 38 else { return nil }
        let rateIndex = Int(frameSizeCode >> 1)
        // Words per frame at 48 kHz are twice the bit rate in kb/s, so bytes per 32 ms frame are four times the rate.
        self.frameBytes = Self.bitRatesKbps[rateIndex] * 4
        self.bitRateCode = UInt8(rateIndex)
        self.fscod = fscod
        self.bsid = bytes[base + 5] >> 3
        self.bsmod = bytes[base + 5] & 0x07
        let acmod = bytes[base + 6] >> 5
        self.acmod = acmod
        // Bit offsets count from the first byte of the frame. acmod occupies bits 48 to 50, so the optional mix levels
        // start at bit 51, and lfeon follows them even when it falls into the next byte.
        var position = 6 * 8 + 3
        func readBit() -> UInt8 {
            let value = (bytes[base + position / 8] >> UInt8(7 - position % 8)) & 1
            position += 1
            return value
        }
        if acmod & 0x1 != 0, acmod != 0x1 { position += 2 }
        if acmod & 0x4 != 0 { position += 2 }
        if acmod == 0x2 { position += 2 }
        guard bytes.endIndex > base + position / 8 else { return nil }
        self.lfe = readBit() == 1
        self.channels = Self.channelsByMode[Int(acmod)] + (lfe ? 1 : 0)
    }

    /// The three-byte `dac3` configuration: fscod, bsid, bsmod, acmod, lfeon, bit_rate_code, then five reserved bits.
    var dac3: Data {
        let value =
            (UInt32(fscod) << 22) | (UInt32(bsid) << 17) | (UInt32(bsmod) << 14) | (UInt32(acmod) << 11)
            | ((lfe ? 1 : 0) << 10) | (UInt32(bitRateCode) << 5)
        return Data([UInt8(value >> 16), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }
}

/// Splits a raw AC-3 stream, as the encoder writes it, into syncframes. A partial frame stays buffered until more bytes
/// arrive. Bytes before a sync word are discarded.
struct AC3Splitter {
    private var pending = Data()

    mutating func append(_ bytes: Data) -> [Data] {
        pending.append(bytes)
        var frames: [Data] = []
        var index = pending.startIndex
        while true {
            while index + 1 < pending.endIndex, !(pending[index] == 0x0B && pending[index + 1] == 0x77) {
                index += 1
            }
            guard index + 8 <= pending.endIndex, let info = AC3SyncInfo(pending[index...]),
                index + info.frameBytes <= pending.endIndex
            else { break }
            frames.append(Data(pending[index..<(index + info.frameBytes)]))
            index += info.frameBytes
        }
        pending = Data(pending[min(index, pending.endIndex)...])
        return frames
    }
}
