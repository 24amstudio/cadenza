import Foundation

enum SingSeparatorFactory {
    static func defaultBackend() -> SingSeparator {
        // MLX model loading can terminate the process inside the native runtime
        // before Swift receives an error. Keep the shipped startup path entirely
        // process-safe until the native failure is fixed and verified on macOS.
        return StereoCenterSuppressor()
    }
}
