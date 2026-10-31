// Music shows the audio tier as a badge on its mini player. These are the tier names the Remote displays.
enum MusicQuality {
    static func tier(forBadge label: String) -> String {
        let text = label.lowercased()
        if text.contains("dolby atmos") { return "dolby_atmos" }
        if text.contains("hi-res") { return "hi_res_lossless" }
        if text.contains("lossless") { return "lossless" }
        return "unknown"
    }
}
