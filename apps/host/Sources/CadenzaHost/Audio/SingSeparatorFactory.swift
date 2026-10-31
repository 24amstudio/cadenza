import Foundation

enum SingSeparatorFactory {
    static func defaultBackend() -> SingSeparator {
        MLXSingSeparator()
    }
}
