import AppKit
import Foundation

@MainActor
final class MusicBridge {
    let accessibility = MusicAccessibility()
    let automation = MusicAutomationChecker()
    /// Replaces the osascript process in tests, so the coordinator's dispatch and verification run without Music.
    var scriptRunner: (@MainActor ([String]) async throws -> Data)?
    var logger: HostLogger? {
        didSet { accessibility.logger = logger }
    }

    /// `deadline` is the last moment the action may still be dispatched. Unless `boundsRuntime` is false it also caps how
    /// long the script may run, which suits reads. A dispatched action is never cut short by the dispatch deadline.
    private func script(
        _ arguments: [String], deadline: Int64? = nil, timeout limit: TimeInterval = 2, boundsRuntime: Bool = true
    ) async throws -> Data {
        if let deadline, monotonicMs() >= deadline {
            throw CadenzaError.failure("expired", "The action expired before dispatch.")
        }
        if let scriptRunner { return try await scriptRunner(arguments) }
        guard let url = HostResources.bundle.url(forResource: "music", withExtension: "js", subdirectory: "Resources")
        else {
            throw CadenzaError.failure("music_unavailable", "The Music automation script is missing.")
        }
        let timeout =
            deadline.flatMap { boundsRuntime ? min(1.5, max(0.05, Double($0 - monotonicMs()) / 1_000)) : nil } ?? limit
        let started = monotonicMs()
        do {
            let data = try await Subprocess.run(
                "/usr/bin/osascript", ["-l", "JavaScript", url.path] + arguments, timeout: timeout)
            automation.markGranted()
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
        // A slow poll that succeeded is timing data, not a warning. Only a failed call is one.
        logger?.log(
            failure == nil ? .info : .warning, category: "music", action: "music." + action,
            failure?.localizedDescription ?? "Music \(action) finished",
            metadata: [
                "ms": String(elapsed), "outcome": failure == nil ? "ok" : "failed",
                "arguments": String(detail.prefix(160)),
            ])
    }

    func status(deadline: Int64? = nil) async throws -> MusicStatus {
        let started = monotonicMs()
        var status = try await Wire.decode(MusicStatus.self, from: script(["status"], deadline: deadline))

        status.sampledAtMs = MusicStatus.sampleTime(
            readAtMs: status.readAtMs, startedMs: started, finishedMs: monotonicMs(), nowWallMs: wallMs())

        return status
    }

    func librarySearch(_ query: String) async throws -> [Song] {
        // Broad queries scan the whole library and take over 2 seconds to describe their results.
        do {
            return try await Wire.decode([Song].self, from: script(["search", query], timeout: 8))
        } catch { throw Self.libraryFailure(error) }
    }

    func resolve(_ identity: SongIdentity) async throws -> Song {
        guard identity.source == "library", Wire.validate(identity) else {
            throw CadenzaError.failure("invalid_command", "Invalid library track.")
        }
        do {
            return try await Wire.decode(Song.self, from: script(["resolve", identity.id]))
        } catch { throw Self.libraryFailure(error) }
    }

    /// Music reports a library track it cannot find as an Apple event error. A Remote gets a plain answer instead.
    private static func libraryFailure(_ error: Error) -> Error {
        guard let failure = error as? CadenzaError, failure.code == "music_unavailable" else { return error }
        let text = failure.localizedDescription
        guard text.contains("(-2700)") || text.contains("library track is unavailable") else { return error }
        return CadenzaError.failure("not_found", "This song is no longer in your Music library.")
    }

    // Music's own artwork is the authority for the track it plays, including streams with no catalog match.
    /// Sets the Favorite flag of a library song in Music. No other field of the song changes.
    func setFavorite(_ identity: SongIdentity, favorite: Bool) async throws {
        let arguments = try MusicLibraryWriteBack.favoriteArguments(identity, favorite: favorite)
        _ = try await script(arguments, timeout: 6)
    }

    /// Adds library songs to the named playlist, which Music creates when it is missing. Returns the number added.
    func addToPlaylist(named name: String, _ identities: [SongIdentity]) async throws -> Int {
        let arguments = try MusicLibraryWriteBack.playlistArguments(name: name, identities)
        struct Reply: Decodable { let added: Int }
        let data = try await script(arguments, timeout: 15)
        return try Wire.decode(Reply.self, from: data).added
    }

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

    /// Music's own next-track command. It needs no focus. While Music is stopped it does nothing, so a caller that
    /// needs playback to start follows it with `resume`.
    func skipToNext(deadline: Int64) async throws {
        _ = try await script(["skip"], deadline: deadline)
    }

    /// Music's own play command. With nothing playing it starts the track Music has loaded.
    func resume(deadline: Int64) async throws {
        _ = try await script(["resume"], deadline: deadline)
    }

    /// Dispatches one transport action and returns Music's state read right after it, when the script could read it.
    /// `deadline` gates dispatch only: once Music has the action, the script runs to its own limit.
    @discardableResult
    func control(_ action: CommandAction, deadline: Int64) async throws -> MusicStatus? {
        let arguments = try Self.controlArguments(action)
        let started = monotonicMs()
        let output: Data
        do {
            output = try await script(arguments, deadline: deadline, timeout: 3, boundsRuntime: false)
        } catch let error where MusicTransportFallback.isAutomationDenial(error) {
            // Music refused Cadenza's Apple events and ran nothing, so a system route may take the action instead.
            guard MusicTransportFallback.perform(action.kind) else { throw error }
            return nil
        }
        guard var status = try? Wire.decode(ControlReply.self, from: output).status else { return nil }

        status.sampledAtMs = MusicStatus.sampleTime(
            readAtMs: status.readAtMs, startedMs: started, finishedMs: monotonicMs(), nowWallMs: wallMs())

        return status
    }

    private struct ControlReply: Decodable {
        var status: MusicStatus?
    }

    static func controlArguments(_ action: CommandAction) throws -> [String] {
        let operation = action.kind.replacingOccurrences(of: "playback.", with: "")
        switch operation {
        case "pause", "resume", "skip", "previous", "stop": return [operation]
        case "seek":
            guard let position = action.positionMs else { break }
            return [operation, String(position)]
        case "volume":
            guard let percent = action.percent else { break }
            return [operation, String(percent)]
        case "shuffle":
            guard let enabled = action.enabled else { break }
            return [operation, enabled ? "true" : "false"]
        case "repeat":
            guard let mode = action.mode, ["off", "one", "all"].contains(mode) else { break }
            return [operation, mode]
        default: break
        }
        throw CadenzaError.failure("invalid_command", "Unknown playback action.")
    }

    func prepare(_ song: Song, isCurrent: () -> Bool) async throws {
        try accessibility.requireAccess()
        let songDetails = ["song": song.source + ":" + song.id, "artist": song.artist]
        logger?.log(
            .info, category: "music", action: "prepare.started", "Preparing \(song.title) in Music",
            metadata: songDetails)
        if song.source == "library" {
            do { _ = try await script(["reveal", song.id]) } catch { throw Self.libraryFailure(error) }
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
            guard let url = components.url else {
                throw CadenzaError.failure("music_unavailable", "Music could not open this song.")
            }
            // Music is opened in the background so the user's current app keeps focus. If Music then exposes no
            // window to Accessibility, selectSong brings it forward once and hands focus back afterwards.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            do {
                _ = try await NSWorkspace.shared.open(url, configuration: configuration)
            } catch {
                throw CadenzaError.failure("music_unavailable", "Music could not open this song.")
            }
        }
        // The music:// link already opens the album with this track selected, so only the selection is checked here. Each
        // pass has its own budget, so one slow Accessibility read cannot consume the whole wait.
        let started = monotonicMs()
        let deadline = started + 12_000
        var lastStep: String?
        repeat {
            try Task.checkCancellation()
            guard isCurrent() else {
                throw CadenzaError.failure("busy", "A newer Music action took priority. Prepare this song again.")
            }
            let pass = min(deadline, monotonicMs() + 1_800)
            guard let issue = try await accessibility.preparationIssue(song, deadline: pass) else {
                logger?.log(
                    .info, category: "music", action: "prepare.completed", "Prepared \(song.title) in Music",
                    metadata: songDetails.merging(["ms": String(monotonicMs() - started)]) { $1 })
                return
            }
            // Each distinct reason is written once, so a long wait does not repeat the same line every pass.
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
