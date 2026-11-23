// Music shows the audio tier as a badge on its mini player. These are the tier names the Remote displays.
enum MusicQuality {
    static func tier(forBadge label: String) -> String {
        let text = label.lowercased()
        if text.contains("dolby atmos") { return "dolby_atmos" }
        if text.contains("hi-res") { return "hi_res_lossless" }
        if text.contains("lossless") { return "lossless" }
        return "unknown"
    }

    /// The codec named by Music's file kind. It is used only when Music shows no tier badge, so a lossless badge always wins.
    static func tier(forFileKind kind: String?) -> String? {
        guard let kind, kind.localizedCaseInsensitiveContains("AAC") else { return nil }
        return "aac"
    }
}
