import Foundation

/// Converts a Cadenza LyricDocument into a WebVTT karaoke rendition (`lyrics.vtt`) for AirPlay 2 HLS subtitle injection.
enum WebVTTKaraoke {
    static func render(document: LyricDocument, userOffsetMs: Int = 0, lipSyncOffsetMs: Int = 0) -> String {
        let totalOffset = Int64(userOffsetMs + lipSyncOffsetMs)
        var blocks: [String] = ["WEBVTT"]
        for (index, line) in document.lines.enumerated() {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let startMs = max(0, line.startMs + totalOffset)
            let nextStart =
                index + 1 < document.lines.count ? max(0, document.lines[index + 1].startMs + totalOffset) : nil
            let rawEnd =
                line.endMs > line.startMs ? max(0, line.endMs + totalOffset) : (nextStart ?? (startMs + 4_000))
            let endMs = max(startMs + 250, rawEnd)
            var cue = "\(timestamp(ms: startMs)) --> \(timestamp(ms: endMs))\n\(text)"
            if let translation = line.translation?.trimmingCharacters(in: .whitespacesAndNewlines),
                !translation.isEmpty
            {
                cue += "\n\(translation)"
            }
            blocks.append(cue)
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    static func timestamp(ms: Int64) -> String {
        let clamped = max(0, ms)
        let hours = clamped / 3_600_000
        let minutes = (clamped % 3_600_000) / 60_000
        let seconds = (clamped % 60_000) / 1_000
        let millis = clamped % 1_000
        return String(format: "%02lld:%02lld:%02lld.%03lld", hours, minutes, seconds, millis)
    }
}
