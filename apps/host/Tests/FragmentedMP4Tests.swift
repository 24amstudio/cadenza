import Foundation
import Testing

@testable import CadenzaHost

struct FragmentedMP4Tests {
    /// The top-level boxes of a buffer, as (type, payload) pairs. A malformed size fails the test.
    private func boxes(_ data: Data) throws -> [(String, Data)] {
        var result: [(String, Data)] = []
        var offset = 0
        while offset < data.count {
            let size = Int(try #require(readUInt32(data, at: offset)))
            try #require(size >= 8 && offset + size <= data.count)
            let type = String(decoding: data[(offset + 4)..<(offset + 8)], as: UTF8.self)
            result.append((type, data.subdata(in: (offset + 8)..<(offset + size))))
            offset += size
        }
        return result
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        return data[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    @Test func anAACInitSegmentHasFtypAndAnMP4AudioTrackWithItsConfiguration() throws {
        let initSegment = FragmentedMP4.initSegment(.aac(channels: 2, sampleRate: 48_000))
        let top = try boxes(initSegment)
        #expect(top.map(\.0) == ["ftyp", "moov"])
        let moov = try #require(top.last?.1)
        #expect(String(decoding: moov, as: UTF8.self).contains("mp4a"))
        #expect(String(decoding: moov, as: UTF8.self).contains("esds"))
        #expect(FragmentedMP4.audioSpecificConfig(channels: 2, sampleRate: 48_000) == Data([0x11, 0x90]))
        #expect(FragmentedMP4.audioSpecificConfig(channels: 2, sampleRate: 44_100) == Data([0x12, 0x10]))
    }

    @Test func anAC3InitSegmentCarriesTheDac3Configuration() throws {
        let dac3 = Data([0x10, 0x3E, 0x40])
        let initSegment = FragmentedMP4.initSegment(.ac3(channels: 6, sampleRate: 48_000, dac3: dac3))
        let moov = try #require(try boxes(initSegment).last?.1)
        #expect(String(decoding: moov, as: UTF8.self).contains("ac-3"))
        #expect(moov.range(of: dac3) != nil)
    }

    @Test func aFragmentPointsItsDataOffsetAtTheFirstSampleAndCarriesEverySample() throws {
        let samples = [Data([1, 2, 3]), Data([4, 5])]
        let fragment = FragmentedMP4.fragment(
            .aac(channels: 2, sampleRate: 48_000), sequence: 7, baseTime: 2_048, sampleDuration: 1_024, samples: samples
        )
        let top = try boxes(fragment)
        #expect(top.map(\.0) == ["moof", "mdat"])
        let mdatPayload = try #require(top.last?.1)
        #expect(mdatPayload == Data([1, 2, 3, 4, 5]))

        let moofSize = try #require(readUInt32(fragment, at: 0))
        let trunDataOffset = try #require(fragment.range(of: Data("trun".utf8)).map { $0.lowerBound })
        let dataOffsetField = trunDataOffset + 4 + 4 + 4
        let dataOffset = try #require(readUInt32(fragment, at: dataOffsetField))
        #expect(Int(dataOffset) == Int(moofSize) + 8)
        #expect(Int(dataOffset) + mdatPayload.count == fragment.count)
    }

    @Test func aSyncframeHeaderGivesTheChannelsAndBitRate() throws {
        let frame = syncframe(acmodLFE: 0xE1)
        let info = try #require(AC3SyncInfo(frame))
        #expect(info.channels == 6)
        #expect(info.lfe)
        #expect(info.frameBytes == 2_560)
        #expect(info.dac3 == Data([0x10, 0x3E, 0x40]))
    }

    @Test func aSplitterReturnsWholeFramesEvenWhenTheyArriveInPieces() {
        let stream = syncframe(acmodLFE: 0xE1) + syncframe(acmodLFE: 0xE1)
        var splitter = AC3Splitter()
        var frames: [Data] = []
        var offset = 0
        while offset < stream.count {
            let end = min(stream.count, offset + 1_000)
            frames += splitter.append(stream.subdata(in: offset..<end))
            offset = end
        }
        #expect(frames.count == 2)
        #expect(frames.allSatisfy { $0.count == 2_560 })
    }

    /// A 640 kb/s, 5.1, 48 kHz syncframe header followed by zero payload to its full length.
    private func syncframe(acmodLFE: UInt8) -> Data {
        var bytes = Data(count: 2_560)
        bytes[0] = 0x0B
        bytes[1] = 0x77
        bytes[4] = 0x24
        bytes[5] = 0x40
        bytes[6] = acmodLFE
        return bytes
    }
}
