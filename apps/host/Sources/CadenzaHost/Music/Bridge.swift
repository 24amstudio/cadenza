import AppKit
import Foundation

@MainActor
final class MusicBridge {
    let accessibility = MusicAccessibility()

    private func script(_ arguments: [String], deadline: Int64? = nil) async throws -> Data {
        if let deadline, monotonicMs() >= deadline {
            throw CadenzaError.failure("expired", "The action expired before dispatch.")
        }
        guard let url = HostResources.bundle.url(forResource: "music", withExtension: "js", subdirectory: "Resources")
        else {
            throw CadenzaError.failure("music_unavailable", "The Music automation script is missing.")
        }
        let timeout = deadline.map { min(0.9, max(0.01, Double($0 - monotonicMs()) / 1_000)) } ?? 2
        return try await Subprocess.run(
            "/usr/bin/osascript", ["-l", "JavaScript", url.path] + arguments, timeout: timeout)
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
        let deadline = monotonicMs() + 12_000
        var lastStep: String?
        if song.source == "catalog" {
            let searchDeadline = min(deadline - 2_000, monotonicMs() + 6_000)
            do {
                let found = try await accessibility.searchCatalog(song, deadline: searchDeadline)
                if !found { lastStep = "Music's search did not show exactly one matching result." }
            } catch {
                lastStep = error.localizedDescription
            }
        }
        repeat {
            try Task.checkCancellation()
            guard isCurrent() else {
                throw CadenzaError.failure("busy", "A newer Music action took priority. Prepare this song again.")
            }
            do {
                try accessibility.showQueue(deadline: min(deadline, monotonicMs() + 250))
            } catch {
                lastStep = error.localizedDescription
            }
            guard let issue = accessibility.preparationIssue(song) else { return }
            lastStep = issue
            try await Task.sleep(for: .milliseconds(150))
        } while monotonicMs() < deadline
        let step = lastStep.map { " Last step: \($0)" } ?? ""
        throw CadenzaError.failure(
            "song_not_ready",
            "Music did not expose the exact song after navigation.\(step) Retry the preparation action.")
    }
}
