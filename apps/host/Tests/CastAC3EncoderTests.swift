import AVFAudio
import Foundation
import Testing

@testable import CadenzaHost

// Collects the helper's output on its reader thread and hands it back to the test.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.append(chunk)
    }

    var snapshot: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

struct CastAC3EncoderTests {
    @Test func aBuildWithoutTheHelperHasNoAC3Encoder() throws {
        let bundle = try #require(Bundle(path: NSTemporaryDirectory()))

        #expect(CastAC3Encoder.helperURL(in: bundle) == nil)
    }

    @Test func aHelperThatCannotRunIsRefusedInsteadOfStartingAnEncoder() {
        let missing = URL(fileURLWithPath: "/nonexistent/cadenza-ac3")

        #expect(CastAC3Encoder(helper: missing, sampleRate: 48_000, onOutput: { _ in }) == nil)
    }

    // Runs only when CADENZA_AC3_HELPER names the built helper. It encodes a second of 5.1 tones and checks the output
    // starts with the AC-3 sync word.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CADENZA_AC3_HELPER"] != nil))
    func fiveOneFloatPCMEncodesToAnAC3Stream() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["CADENZA_AC3_HELPER"])
        let collected = OutputCollector()
        let encoder = CastAC3Encoder(
            helper: URL(fileURLWithPath: path), sampleRate: 48_000, onOutput: { collected.append($0) })
        guard let encoder else {
            Issue.record("The helper at \(path) did not start.")

            return
        }
        let layout = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_5_1_D))
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channelLayout: layout)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        buffer.frameLength = 48_000
        let channels = try #require(buffer.floatChannelData)
        for channel in 0..<6 {
            for frame in 0..<48_000 {
                channels[channel][frame] = Float(
                    0.3 * sin(2 * Double.pi * Double(220 * (channel + 1)) * Double(frame) / 48_000))
            }
        }

        encoder.encode(buffer)
        try await Task.sleep(for: .seconds(2))
        encoder.stop()
        try await Task.sleep(for: .seconds(1))

        let output = collected.snapshot
        #expect(output.count > 0)
        #expect(output.prefix(2) == Data([0x0B, 0x77]))
    }
}
