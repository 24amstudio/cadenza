import AppKit
import Foundation
import WebKit

@MainActor
final class SingPageWindow: NSObject, NSWindowDelegate {
    let accessToken = SingPageWindow.makeAccessToken()
    var onUserClosed: (@MainActor () -> Void)?
    private var window: NSWindow?
    private var webView: WKWebView?
    private var requestedURL: URL?
    private var leavingFullScreen = false

    func show(url: URL) {
        let window = window ?? makeWindow()
        if requestedURL != url {
            requestedURL = url
            webView?.load(URLRequest(url: url))
        }
        if leavingFullScreen {
            leavingFullScreen = false
            return
        }
        guard !window.isVisible else { return }
        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)
    }

    func hide() {
        guard let window, window.isVisible, !leavingFullScreen else { return }
        guard window.styleMask.contains(.fullScreen) else {
            window.orderOut(nil)
            return
        }
        leavingFullScreen = true
        window.toggleFullScreen(nil)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        guard leavingFullScreen else { return }
        leavingFullScreen = false
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onUserClosed?()
    }

    private func makeWindow() -> NSWindow {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.underPageBackgroundColor = .black
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_280, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Cadenza Sing"
        window.backgroundColor = .black
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.delegate = self
        window.center()
        self.window = window
        self.webView = webView
        return window
    }

    private static func makeAccessToken() -> String {
        (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
    }
}
