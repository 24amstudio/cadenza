import Foundation

/// Writes the minimal fragmented MP4 boxes a Media Source buffer needs for one audio track: an init segment (`ftyp` and
/// `moov`) and one `moof` + `mdat` fragment per group of access units. The timescale is the sample rate, so durations
/// are in samples.
enum FragmentedMP4 {
    enum Track: Equatable {
        /// AAC-LC access units without ADTS headers.
        case aac(channels: Int, sampleRate: Int)
        /// AC-3 syncframes. `dac3` is the three-byte configuration from `AC3SyncInfo.dac3`.
        case ac3(channels: Int, sampleRate: Int, dac3: Data)

        var sampleRate: Int {
            switch self {
            case .aac(_, let rate), .ac3(_, let rate, _): rate
            }
        }

        var channels: Int {
            switch self {
            case .aac(let channels, _), .ac3(let channels, _, _): channels
            }
        }
    }

    static let trackID: UInt32 = 1

    static func initSegment(_ track: Track) -> Data {
        box("ftyp", Data("iso5".utf8) + u32(0) + Data("iso5iso6mp41".utf8))
            + box("moov", movieHeader(track) + trak(track) + mvex())
    }

    /// One fragment. `samples` are access units of `sampleDuration` samples each, and `baseTime` is the first sample's
    /// decode time in the track timescale.
    static func fragment(_ track: Track, sequence: UInt32, baseTime: UInt64, sampleDuration: UInt32, samples: [Data])
        -> Data
    {
        let sizes = samples.map(\.count)
        // The data offset is the moof length plus the mdat header. The moof length does not depend on that value.
        let moofWithoutOffset = box(
            "moof",
            mfhd(sequence)
                + traf(baseTime: baseTime, sampleDuration: sampleDuration, sizes: sizes, dataOffset: 0))
        let moof = box(
            "moof",
            mfhd(sequence)
                + traf(
                    baseTime: baseTime, sampleDuration: sampleDuration, sizes: sizes,
                    dataOffset: Int32(moofWithoutOffset.count + 8)))
        return moof + box("mdat", samples.reduce(Data()) { $0 + $1 })
    }

    // MARK: Init segment

    private static func movieHeader(_ track: Track) -> Data {
        var payload = u32(0) + u32(0) + u32(UInt32(track.sampleRate)) + u32(0)
        payload += u32(0x0001_0000) + u16(0x0100) + Data(count: 10) + matrix + Data(count: 24) + u32(trackID + 1)
        return box("mvhd", fullBox(version: 0, flags: 0, payload))
    }

    private static func trak(_ track: Track) -> Data {
        var tkhd = u32(0) + u32(0) + u32(trackID) + u32(0) + u32(0) + Data(count: 8)
        tkhd += u16(0) + u16(0) + u16(0x0100) + u16(0) + matrix + u32(0) + u32(0)
        let mdhd = u32(0) + u32(0) + u32(UInt32(track.sampleRate)) + u32(0) + u16(0x55C4) + u16(0)
        let hdlr = u32(0) + Data("soun".utf8) + Data(count: 12) + Data("Cadenza\0".utf8)
        let smhd = u16(0) + u16(0)
        let dref = u32(1) + box("url ", fullBox(version: 0, flags: 1, Data()))
        let dinf = box("dinf", box("dref", fullBox(version: 0, flags: 0, dref)))
        let stbl = box(
            "stbl",
            box("stsd", fullBox(version: 0, flags: 0, u32(1) + sampleEntry(track)))
                + box("stts", fullBox(version: 0, flags: 0, u32(0)))
                + box("stsc", fullBox(version: 0, flags: 0, u32(0)))
                + box("stsz", fullBox(version: 0, flags: 0, u32(0) + u32(0)))
                + box("stco", fullBox(version: 0, flags: 0, u32(0))))
        let minf = box("minf", box("smhd", fullBox(version: 0, flags: 0, smhd)) + dinf + stbl)
        let mdia = box(
            "mdia",
            box("mdhd", fullBox(version: 0, flags: 0, mdhd)) + box("hdlr", fullBox(version: 0, flags: 0, hdlr)) + minf)
        return box("trak", box("tkhd", fullBox(version: 0, flags: 3, tkhd)) + mdia)
    }

    private static func sampleEntry(_ track: Track) -> Data {
        let audioHeader =
            Data(count: 6) + u16(1) + Data(count: 8) + u16(UInt16(track.channels)) + u16(16)
            + u16(0) + u16(0) + u32(UInt32(track.sampleRate) << 16)
        switch track {
        case .aac(let channels, let rate):
            return box(
                "mp4a",
                audioHeader
                    + box(
                        "esds",
                        fullBox(
                            version: 0, flags: 0,
                            esDescriptor(audioSpecificConfig(channels: channels, sampleRate: rate)))))
        case .ac3(_, _, let dac3):
            return box("ac-3", audioHeader + box("dac3", dac3))
        }
    }

    private static func mvex() -> Data {
        box("mvex", box("trex", fullBox(version: 0, flags: 0, u32(trackID) + u32(1) + u32(0) + u32(0) + u32(0))))
    }

    /// AAC-LC AudioSpecificConfig: object type 2, the sampling-frequency index, and the channel configuration.
    static func audioSpecificConfig(channels: Int, sampleRate: Int) -> Data {
        let frequencyIndex: UInt16 = sampleRate == 44_100 ? 4 : 3
        let value = (UInt16(2) << 11) | (frequencyIndex << 7) | (UInt16(channels) << 3)
        return Data([UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    private static func esDescriptor(_ config: Data) -> Data {
        let decoderSpecific = Data([0x05, UInt8(config.count)]) + config
        let decoderConfig =
            Data([0x04, UInt8(13 + decoderSpecific.count), 0x40, 0x15, 0, 0, 0])
            + u32(192_000) + u32(192_000) + decoderSpecific
        let sl = Data([0x06, 0x01, 0x02])
        return Data([0x03, UInt8(3 + decoderConfig.count + sl.count), 0x00, 0x01, 0x00]) + decoderConfig + sl
    }

    // MARK: Fragment

    private static func mfhd(_ sequence: UInt32) -> Data {
        box("mfhd", fullBox(version: 0, flags: 0, u32(sequence)))
    }

    /// One track run with a sample duration and size for each access unit. The flags say which fields are present.
    private static func traf(baseTime: UInt64, sampleDuration: UInt32, sizes: [Int], dataOffset: Int32) -> Data {
        let flags: UInt32 = 0x000301  // data offset, sample duration, and sample size are present.
        let tfhd = box("tfhd", fullBox(version: 0, flags: 0x020000, u32(trackID)))
        let tfdt = box("tfdt", fullBox(version: 1, flags: 0, u64(baseTime)))
        var body = u32(UInt32(sizes.count)) + u32(UInt32(bitPattern: dataOffset))
        for size in sizes { body += u32(sampleDuration) + u32(UInt32(size)) }
        return box("traf", tfhd + tfdt + box("trun", fullBox(version: 0, flags: flags, body)))
    }

    // MARK: Boxes

    private static let matrix =
        u32(0x0001_0000) + u32(0) + u32(0) + u32(0) + u32(0x0001_0000) + u32(0) + u32(0) + u32(0)
        + u32(0x4000_0000)

    static func box(_ type: String, _ payload: Data) -> Data {
        u32(UInt32(8 + payload.count)) + Data(type.utf8) + payload
    }

    private static func fullBox(version: UInt8, flags: UInt32, _ payload: Data) -> Data {
        Data([version]) + Data([UInt8(flags >> 16), UInt8((flags >> 8) & 0xFF), UInt8(flags & 0xFF)]) + payload
    }

    private static func u16(_ value: UInt16) -> Data { Data([UInt8(value >> 8), UInt8(value & 0xFF)]) }

    private static func u32(_ value: UInt32) -> Data {
        Data([UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }

    private static func u64(_ value: UInt64) -> Data { u32(UInt32(value >> 32)) + u32(UInt32(value & 0xFFFF_FFFF)) }
}
