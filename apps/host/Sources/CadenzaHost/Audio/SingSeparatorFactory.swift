import Foundation

enum SingSeparatorFactory {
    static func defaultBackend() -> SingSeparator {
        // MLX model loading can terminate the process inside the native runtime
        // before Swift receives an error. Keep normal Sing startup process-safe;
        // developers can explicitly opt into MLX after validating the runtime.
        if ProcessInfo.processInfo.environment["CADENZA_SING_BACKEND"] == "mlx" {
            return MLXSingSeparator()
        }
        return StereoCenterSuppressor()
    }
}
