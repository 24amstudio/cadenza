import AppKit
import Foundation

/// Music's distributed event is a hint, never the authority. Bounded native readback remains the fallback.
@MainActor
final class MusicObservation {
    private var musicToken: NSObjectProtocol?
    private var wakeToken: NSObjectProtocol?
    private var coalesced: Task<Void, Never>?

    func start(refresh: @escaping @MainActor () async -> Void) {
        stop()
        musicToken = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.schedule(refresh) }
        }
        wakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.schedule(refresh) }
        }
    }

    private func schedule(_ refresh: @escaping @MainActor () async -> Void) {
        guard coalesced == nil else { return }
        coalesced = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            await refresh()
            self?.coalesced = nil
        }
    }

    func stop() {
        coalesced?.cancel()
        coalesced = nil
        if let musicToken { DistributedNotificationCenter.default().removeObserver(musicToken) }
        if let wakeToken { NSWorkspace.shared.notificationCenter.removeObserver(wakeToken) }
        musicToken = nil
        wakeToken = nil
    }
}
