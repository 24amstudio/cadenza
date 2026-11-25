import AVFAudio
import Foundation

/// Encodes six-channel PCM as AC-3 with the helper that ships in the app bundle. The helper is an FFmpeg build that holds
/// only the AC-3 encoder. It reads interleaved 32-bit float PCM on stdin and writes an AC-3 stream on stdout. Stereo stays
/// on the AAC path, so this encoder runs only for 5.1 output.
final class CastAC3Encoder: @unchecked Sendable {
    static let helperName = "cadenza-ac3"
    static let channelCount = 6

    private let process = Process()
    private let input: FileHandle
    // Writes run off the audio callback, so a slow encoder never holds up capture.
    private let writes = DispatchQueue(label: "app.cadenza.host.cast.ac3-input")

    /// The helper in the bundle, or nil when this build does not include it.
    static func helperURL(in bundle: Bundle = .main) -> URL? {
        let url = bundle.bundleURL.appending(path: "Contents/Helpers/\(helperName)")

        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static func arguments(sampleRate: Double) -> [String] {
        [
            "-hide_banner", "-loglevel", "error",
            "-f", "f32le", "-ar", String(Int(sampleRate)), "-ac", String(channelCount), "-i", "pipe:0",
            "-c:a", "ac3", "-b:a", "640k", "-f", "ac3", "pipe:1",
        ]
    }

    init?(helper: URL, sampleRate: Double, onOutput: @escaping @Sendable (Data) -> Void) {
        let stdin = Pipe()
        let stdout = Pipe()
        process.executableURL = helper
        process.arguments = Self.arguments(sampleRate: sampleRate)
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil

                return
            }
            onOutput(data)
        }
        do {
            try process.run()
        } catch {
            return nil
        }
        input = stdin.fileHandleForWriting
    }

    /// Queues one buffer of non-interleaved float channels, written to the helper as interleaved frames.
    func encode(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData, buffer.format.channelCount == Self.channelCount else { return }
        let frames = Int(buffer.frameLength)
        var interleaved = [Float](repeating: 0, count: frames * Self.channelCount)
        for frame in 0..<frames {
            for channel in 0..<Self.channelCount {
                interleaved[frame * Self.channelCount + channel] = channels[channel][frame]
            }
        }
        let data = interleaved.withUnsafeBytes { Data($0) }
        let input = input
        writes.async { try? input.write(contentsOf: data) }
    }

    /// Ends the stream after the writes already queued. The helper finishes its last frames and exits on end of input.
    func stop() {
        let input = input
        writes.async { try? input.close() }
    }
}
