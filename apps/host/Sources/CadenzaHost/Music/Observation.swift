import AppKit
import Foundation

/// Music's distributed event is a hint, never the authority. Bounded native readback remains the fallback.
@MainActor
final class MusicObservation {
    private var musicToken: NSObjectProtocol?
    private var wakeToken: NSObjectProtocol?
    private var screenLockToken: NSObjectProtocol?
    private var coalesced: Task<Void, Never>?
    private var changedDuringRead = false
    private var latestHintAt: Int64 = 0

    /// `refresh` receives the Host time of the latest hint, so it can skip a read that already saw that change.
    func start(refresh: @escaping @MainActor (Int64) async -> Void) {
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
        screenLockToken = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            if note.name == NSNotification.Name("com.apple.screenIsLocked") {
                // Screen is locked; short-circuit any pending Accessibility reads
                self.changedDuringRead = true
            } else if note.name == NSNotification.Name("com.apple.screenIsUnlocked") {
                // Screen is unlocked; allow reads to proceed
                self.changedDuringRead = false
            }
        }
    }

    private func schedule(_ refresh: @escaping @MainActor (Int64) async -> Void) {
        latestHintAt = monotonicMs()
        // A hint that arrives while a read runs may describe a newer state than that read saw, so one more read follows.
        guard coalesced == nil else {
            changedDuringRead = true
            return
        }
        coalesced = Task { @MainActor [weak self] in
            repeat {
                self?.changedDuringRead = false
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                await refresh(self?.latestHintAt ?? monotonicMs())
            } while self?.changedDuringRead == true && !Task.isCancelled
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
