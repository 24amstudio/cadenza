import Foundation

struct RemoteAudioPlayoutReport: Equatable, Sendable {
    let underrunFrames: Int
    let concealedFrames: Int
    let longTaskMs: Double

    static let empty = RemoteAudioPlayoutReport(underrunFrames: 0, concealedFrames: 0, longTaskMs: 0)

    private struct Wire: Decodable {
        let version: Int
        let type: String
        let underrunFrames: Int
        let concealedFrames: Int
        let longTaskMs: Double
    }

    static func decode(_ text: Data) -> RemoteAudioPlayoutReport? {
        guard let wire = try? JSONDecoder().decode(Wire.self, from: text),
            wire.version == 1, wire.type == "REMOTE_AUDIO_PLAYOUT",
            (0...1_000_000).contains(wire.underrunFrames), (0...1_000_000).contains(wire.concealedFrames),
            (0...10_000).contains(wire.longTaskMs)
        else { return nil }
        return RemoteAudioPlayoutReport(
            underrunFrames: wire.underrunFrames, concealedFrames: wire.concealedFrames, longTaskMs: wire.longTaskMs)
    }

    func adding(_ other: RemoteAudioPlayoutReport) -> RemoteAudioPlayoutReport {
        RemoteAudioPlayoutReport(
            underrunFrames: underrunFrames + other.underrunFrames,
            concealedFrames: concealedFrames + other.concealedFrames,
            longTaskMs: longTaskMs + other.longTaskMs)
    }
}
