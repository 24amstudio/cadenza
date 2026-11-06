// A song's state waits for its cover when the cover is not cached yet, so the title and the cover reach the Remote
// together. This decides which cover a state must wait for.
enum StateCover {
    static let waitMs: Int64 = 1_500

    // The cover URL a state must wait for, or nil when the state can go out now.
    static func coverToAwait(artworkUrl: String?, isCached: (String) -> Bool, alreadyWaited: String?) -> String? {
        guard let url = artworkUrl, !isCached(url), url != alreadyWaited else { return nil }
        return url
    }
}
