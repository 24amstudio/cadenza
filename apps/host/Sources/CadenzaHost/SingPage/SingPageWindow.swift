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
    private var wantsVisible = false
    private var transitioning = false

    func show(url: URL) {
        let window = window ?? makeWindow()
        let appearing = !wantsVisible
        wantsVisible = true
        if appearing || requestedURL != url {
            requestedURL = url
            webView?.load(URLRequest(url: url))
        }
        if appearing { present(window) }
    }

    func hide() {
        guard let window, wantsVisible else { return }
        wantsVisible = false
        guard !transitioning else { return }
        if window.styleMask.contains(.fullScreen) {
            transitioning = true
            window.toggleFullScreen(nil)
        } else {
            window.orderOut(nil)
        }
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        finishTransition()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        finishTransition()
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        transitioning = false
    }

    func windowDidFailToExitFullScreen(_ window: NSWindow) {
        transitioning = false
    }

    func windowWillClose(_ notification: Notification) {
        wantsVisible = false
        onUserClosed?()
    }

    private func present(_ window: NSWindow) {
        guard !transitioning else { return }
        window.makeKeyAndOrderFront(nil)
        guard !window.styleMask.contains(.fullScreen) else { return }
        transitioning = true
        window.toggleFullScreen(nil)
    }

    private func finishTransition() {
        guard transitioning, let window else { return }
        transitioning = false
        if wantsVisible {
            present(window)
        } else if window.styleMask.contains(.fullScreen) {
            transitioning = true
            window.toggleFullScreen(nil)
        } else {
            window.orderOut(nil)
        }
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
