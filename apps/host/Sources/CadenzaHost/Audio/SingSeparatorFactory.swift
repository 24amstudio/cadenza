import Foundation

enum SingSeparatorFactory {
    /// Production keeps the model-free stereo fallback until a verified Sing model is installed. Development always
    /// selects MLX, which reports a missing model instead of downloading one.
    static func defaultBackend(modelInstalled: Bool) -> SingSeparator {
        HostBuild.profile == "production" && !modelInstalled ? StereoCenterSuppressor() : MLXSingSeparator()
    }
}
