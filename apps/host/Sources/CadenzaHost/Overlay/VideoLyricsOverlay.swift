import AppKit
import ApplicationServices

/// A click-through karaoke line over the lower part of Music's video window. Accessibility notifications keep it on the
/// window as the window moves or resizes, and it is hidden while any other app is frontmost.
@MainActor
final class VideoLyricsOverlay {
    private let window: NSWindow
    private let container = NSView()
    private let label = NSTextField(labelWithString: "")
    private var observer: AXObserver?
    private var musicWindow: AXUIElement?
    private var line: String?
    private var activation: NSObjectProtocol?

    init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
        container.layer?.cornerRadius = 14
        container.autoresizingMask = [.width, .height]

        label.alignment = .center
        label.textColor = .white
        label.font = .systemFont(ofSize: 26, weight: .semibold)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        window.contentView = container

        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshVisibility() }
        }
    }

    isolated deinit {
        detachObserver()
        if let activation {
            NSWorkspace.shared.notificationCenter.removeObserver(activation)
        }
    }

    /// Follows Music's first window. Nil, or a window Accessibility cannot read, detaches the overlay.
    func follow(musicProcess pid: pid_t?) {
        detachObserver()
        guard let pid else {
            refreshVisibility()
            return
        }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.35)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
            let windows = value as? [AXUIElement], let first = windows.first
        else {
            refreshVisibility()
            return
        }
        var created: AXObserver?
        guard AXObserverCreate(pid, Self.axCallback, &created) == .success, let created else {
            refreshVisibility()
            return
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(created, first, kAXMovedNotification as CFString, refcon)
        AXObserverAddNotification(created, first, kAXResizedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        musicWindow = first
        refreshVisibility()
    }

    /// Whether the overlay is following a Music window. It is false until Music has a window to follow.
    var isAttached: Bool { musicWindow != nil }

    /// The line to show, or nil when the current item is not a music video.
    func show(line: String?) {
        self.line = line
        refreshVisibility()
    }

    private func refreshVisibility() {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let visible = VideoLyricsVisibility.shouldShow(
            frontmostBundleIdentifier: frontmost, videoIsCurrent: line != nil, windowIsKnown: musicWindow != nil)
        let text = line ?? ""
        label.stringValue = text
        guard visible, !text.isEmpty else {
            window.orderOut(nil)
            return
        }
        reposition()
        window.orderFrontRegardless()
    }

    private func reposition() {
        guard let musicWindow, let frame = Self.frame(of: musicWindow), let screen = NSScreen.screens.first else {
            return
        }
        let appKit = VideoLyricsOverlayGeometry.appKitFrame(
            accessibilityFrame: frame, primaryDisplayHeight: screen.frame.height)
        window.setFrame(VideoLyricsOverlayGeometry.lyricBand(in: appKit), display: true)
    }

    private func detachObserver() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        musicWindow = nil
    }

    // Accessibility delivers move and resize notifications on the main run loop, where the overlay is main-actor state.
    private static let axCallback: AXObserverCallback = { _, _, _, refcon in
        guard let refcon else { return }
        let overlay = Unmanaged<VideoLyricsOverlay>.fromOpaque(refcon).takeUnretainedValue()
        MainActor.assumeIsolated { overlay.reposition() }
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
            let positionValue, let sizeValue
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: point, size: size)
    }
}
