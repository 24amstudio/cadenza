import Foundation

actor Lyrics {
    private var cache: [String: LyricDocument] = [:]
    private let disk: HostCache
    private let music: any LyricsProvider
    private let fallbackProviders: [any LyricsProvider]
    private struct ProviderMiss: Codable {
        let checkedAtMs: Int64
    }

    init(cache: HostCache, providerEnabled: Bool) {
        disk = cache
        music = MusicLyricsProvider()
        var providers: [any LyricsProvider] = []
        if providerEnabled { providers.append(LRCLIBProvider()) }
        fallbackProviders = providers
    }

    func document(song: Song, occurrence: String) async throws -> LyricDocument {
        let key = song.source + ":" + song.id
        if var known = cache[key] {
            known.occurrenceId = occurrence
            return known
        }
        // Bump this prefix whenever parsed timings change; otherwise documents cached
        // by the older parser keep their wrong timings across restarts.
        if let data = try? await disk.data(for: "lyrics-v2:" + key),
            var known = try? JSONDecoder().decode(LyricDocument.self, from: data)
        {
            known.occurrenceId = occurrence
            cache[key] = known
            return known
        }
        // A malformed or temporarily unavailable Music cache should fall
        // through to LRCLIB instead of preventing a second provider attempt.
        if let document = try? await music.document(song: song, occurrence: occurrence) {
            if cache.count >= 8 { cache.removeAll(keepingCapacity: true) }
            cache[key] = document
            if let data = try? JSONEncoder().encode(document) {
                try? await disk.put(data, for: "lyrics-v2:" + key, kind: "lyrics")
            }
            return document
        }
        if fallbackProviders.isEmpty,
            let data = try? await disk.data(for: "lyrics-miss:" + key),
            let miss = try? JSONDecoder().decode(ProviderMiss.self, from: data),
            wallMs() - miss.checkedAtMs < 900_000
        {
            throw unavailable()
        }
        for provider in fallbackProviders {
            do {
                if let document = try await provider.document(song: song, occurrence: occurrence) {
                    if cache.count >= 8 { cache.removeAll(keepingCapacity: true) }
                    cache[key] = document
                    if let data = try? JSONEncoder().encode(document) {
                        try? await disk.put(data, for: "lyrics-v2:" + key, kind: "lyrics")
                    }
                    try? await disk.remove("lyrics-miss:" + key)
                    return document
                }
            } catch {
                // Provider outages are recoverable. Continue to the next source
                // and let the caller retry Music's local cache before surfacing a
                // user-facing failure.
                continue
            }
        }
        if !fallbackProviders.isEmpty,
            let data = try? JSONEncoder().encode(ProviderMiss(checkedAtMs: wallMs()))
        {
            try? await disk.put(data, for: "lyrics-miss:" + key, kind: "provider")
        }
        throw unavailable()
    }

    private func unavailable() -> CadenzaError {
        .failure(
            "lyrics_unavailable",
            "Lyrics are not available in Music or the configured Host provider yet. Try again later."
        )
    }

    func english(_ document: LyricDocument, song: Song) async -> LyricDocument {
        guard document.language?.hasPrefix("en") != true,
            document.lines.contains(where: { $0.translation == nil })
        else { return document }
        let translated = await EnglishTranslation.translate(document)
        if !Task.isCancelled {
            let key = song.source + ":" + song.id
            cache[key] = translated
            if let data = try? JSONEncoder().encode(translated) {
                try? await disk.put(data, for: "lyrics-v2:" + key, kind: "lyrics")
            }
        }
        return translated
    }
}
