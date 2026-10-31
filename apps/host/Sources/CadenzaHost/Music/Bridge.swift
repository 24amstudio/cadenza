import AppKit
import Foundation

@MainActor
final class MusicBridge {
    let accessibility = MusicAccessibility()
    var logger: HostLogger? {
        didSet { accessibility.logger = logger }
    }

    private func script(_ arguments: [String], deadline: Int64? = nil) async throws -> Data {
        if let deadline, monotonicMs() >= deadline {
            throw CadenzaError.failure("expired", "The action expired before dispatch.")
        }
        guard let url = HostResources.bundle.url(forResource: "music", withExtension: "js", subdirectory: "Resources")
        else {
            throw CadenzaError.failure("music_unavailable", "The Music automation script is missing.")
        }
        let timeout = deadline.map { min(0.9, max(0.01, Double($0 - monotonicMs()) / 1_000)) } ?? 2
        let started = monotonicMs()
        do {
            let data = try await Subprocess.run(
                "/usr/bin/osascript", ["-l", "JavaScript", url.path] + arguments, timeout: timeout)
            logScript(arguments, started: started, failure: nil)
            return data
        } catch {
            logScript(arguments, started: started, failure: error)
            throw error
        }
    }

    // Status polls run continuously, so only slow or failed polls are written. Every other Music action is logged.
    private func logScript(_ arguments: [String], started: Int64, failure: Error?) {
        let action = arguments.first ?? "unknown"
        let elapsed = monotonicMs() - started
        if action == "status", failure == nil, elapsed < 1_000 {
            logger?.count("music.status")
            return
        }
        let detail = arguments.dropFirst().joined(separator: " ")
        logger?.log(
            failure == nil && elapsed < 1_000 ? .info : .warning, category: "music", action: "music." + action,
            failure?.localizedDescription ?? "Music \(action) finished",
            metadata: [
                "ms": String(elapsed), "outcome": failure == nil ? "ok" : "failed",
                "arguments": String(detail.prefix(160)),
            ])
    }

    func status(deadline: Int64? = nil) async throws -> MusicStatus {
        try await Wire.decode(MusicStatus.self, from: script(["status"], deadline: deadline))
    }

    func librarySearch(_ query: String) async throws -> [Song] {
        try await Wire.decode([Song].self, from: script(["search", query]))
    }

    func resolve(_ identity: SongIdentity) async throws -> Song {
        guard identity.source == "library", Wire.validate(identity) else {
            throw CadenzaError.failure("invalid_command", "Invalid library track.")
        }
        return try await Wire.decode(Song.self, from: script(["resolve", identity.id]))
    }

    // Music's own artwork is the authority for the track it plays, including streams with no catalog match.
    func currentArtwork() async throws -> Data? {
        guard
            let script = HostResources.bundle.url(
                forResource: "music-artwork", withExtension: "applescript", subdirectory: "Resources")
        else {
            throw CadenzaError.failure("music_unavailable", "The Music artwork script is missing.")
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cadenza-artwork-" + identifier() + ".bin")
        defer { try? FileManager.default.removeItem(at: output) }
        _ = try await Subprocess.run("/usr/bin/osascript", [script.path, output.path], timeout: 4)
        guard let data = try? Data(contentsOf: output), !data.isEmpty else { return nil }
        return data
    }

    func control(_ action: CommandAction, deadline: Int64) async throws {
        let operation = action.kind.replacingOccurrences(of: "playback.", with: "")
        guard ["pause", "resume", "skip", "previous", "stop", "seek", "volume"].contains(operation) else {
            throw CadenzaError.failure("invalid_command", "Unknown playback action.")
        }
        var arguments = [operation]
        if let position = action.positionMs { arguments.append(String(position)) }
        if let percent = action.percent { arguments.append(String(percent)) }
        _ = try await script(arguments, deadline: deadline)
    }

    func prepare(_ song: Song, isCurrent: () -> Bool) async throws {
        try accessibility.requireAccess()
        let songDetails = ["song": song.source + ":" + song.id, "artist": song.artist]
        logger?.log(
            .info, category: "music", action: "prepare.started", "Preparing \(song.title) in Music",
            metadata: songDetails)
        if song.source == "library" {
            _ = try await script(["reveal", song.id])
        } else {
            guard let value = song.url, var components = URLComponents(string: value),
                components.scheme == "https", components.host == "music.apple.com",
                components.user == nil, components.password == nil,
                components.queryItems?.contains(where: { $0.name == "i" && $0.value == song.id }) == true
                    || components.path.hasSuffix("/\(song.id)")
            else {
                throw CadenzaError.failure("invalid_command", "This catalog result has no verified Music link.")
            }
            components.scheme = "music"
            guard let url = components.url, NSWorkspace.shared.open(url) else {
                throw CadenzaError.failure("music_unavailable", "Music could not open this song.")
            }
            // Opening a music:// URL can leave Music behind another app. Bring its
            // document window forward so Accessibility can select the exact track.
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
                .first?.activate(options: [.activateAllWindows])
        }
        // The music:// link already opens the album with this track selected, so only the selection is checked here.
        let started = monotonicMs()
        let deadline = started + 12_000
        var lastStep: String?
        repeat {
            try Task.checkCancellation()
            guard isCurrent() else {
                throw CadenzaError.failure("busy", "A newer Music action took priority. Prepare this song again.")
            }
            guard let issue = accessibility.preparationIssue(song) else {
                logger?.log(
                    .info, category: "music", action: "prepare.completed", "Prepared \(song.title) in Music",
                    metadata: songDetails.merging(["ms": String(monotonicMs() - started)]) { $1 })
                return
            }
            // Each distinct reason is written once, so a long wait does not repeat the same line every 150 ms.
            if issue != lastStep {
                logger?.log(
                    .debug, category: "music", action: "prepare.waiting", issue, metadata: songDetails)
            }
            lastStep = issue
            try await Task.sleep(for: .milliseconds(150))
        } while monotonicMs() < deadline
        logger?.log(
            .warning, category: "music", action: "prepare.failed",
            lastStep ?? "Music did not expose the song",
            metadata: songDetails.merging(["ms": String(monotonicMs() - started)]) { $1 })
        let step = lastStep.map { " Last step: \($0)" } ?? ""
        throw CadenzaError.failure(
            "song_not_ready",
            "Music did not expose the exact song after navigation.\(step) Retry the preparation action.")
    }
}
