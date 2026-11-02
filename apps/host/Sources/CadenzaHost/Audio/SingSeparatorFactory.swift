import Foundation

enum SingSeparatorFactory {
    static func defaultBackend() -> SingSeparator {
        // Development builds run the MLX separator. Its model loads only when Sing is prepared,
        // not at launch. Production keeps the stereo fallback, which is the only backend its
        // capability check advertises, until MLX has release-build validation.
        HostBuild.profile == "production" ? StereoCenterSuppressor() : MLXSingSeparator()
    }
}
