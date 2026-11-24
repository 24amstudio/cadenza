import AppKit

/// The Menu Bar Only setting, which hides the Dock icon. It is applied before the first window appears, and again
/// whenever the user changes it.
enum HostPresentation {
    static let menuBarOnlyKey = "menuBarOnly"

    static func apply(menuBarOnly: Bool) {
        NSApp.setActivationPolicy(menuBarOnly ? .accessory : .regular)
    }
}
