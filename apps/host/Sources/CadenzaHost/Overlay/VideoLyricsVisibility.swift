/// The karaoke line is shown only while Music is the frontmost app, a music video is the current item, and Music's
/// window is known. Switching to any other app hides it at once, so other work stays unobstructed.
enum VideoLyricsVisibility {
    static let musicBundleIdentifier = "com.apple.Music"

    static func shouldShow(frontmostBundleIdentifier: String?, videoIsCurrent: Bool, windowIsKnown: Bool) -> Bool {
        frontmostBundleIdentifier == musicBundleIdentifier && videoIsCurrent && windowIsKnown
    }
}
