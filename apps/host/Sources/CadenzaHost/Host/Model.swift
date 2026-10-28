import Accessibility
import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class HostModel {
    var snapshot: HostSnapshot?
    var configuration = HostConfiguration.load()
    var remotes: [PairedRemote] = []
    var starting = false
    var saving = false
    var controlling = false
    var running = false
    var prompt: HostPrompt?
    var toast: String?
    var invitation: PairingInvitation?
    var updateBusy = false
    var updateProgress: Double = 0
    var stagedVersion: String?
    var service: HostService?
    var onboardingComplete = UserDefaults.standard.bool(forKey: "onboardingComplete")
    var showingSetup = false
    var selectedTab = 2
    var connectedRemotes: [PairedRemote] = []
    var cacheStats: HostCacheStats?
    var clearingCache = false
    private var updater: HostUpdater?
    private var updateScheduler: NSBackgroundActivityScheduler?
    private var toastTask: Task<Void, Never>?

    func start() async {
        guard !starting, !saving, !running else { return }
        starting = true
        defer { starting = false }
        service?.stop()
        do {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            ).appendingPathComponent("Cadence Host", isDirectory: true)
            let service = try HostService(directory: directory, configuration: configuration)
            self.service = service
            if service.store.database.wasCreated {
                notify("Host storage was recreated. Pair your Remotes again.")
                service.logger.log(.warning, category: "storage", action: "database.recreated", "Host database was recreated")
            }
            service.onSnapshot = { [weak self] value in self?.snapshot = value }
            service.onDevicesChanged = { [weak self] in self?.refreshDevices() }
            service.onIssue = { [weak self] value in
                guard let self else { return }
                self.running = self.service?.network.ready ?? false
                self.showError("Host needs attention", value)
            }
            updater = HostUpdater(directory: directory)
            updater?.onProgress = { [weak self] value in self?.updateProgress = value }
            try await service.start(observing: onboardingComplete)
            running = true
            refreshDevices()
            scheduleUpdates()
            if onboardingComplete { await service.queue.refresh() }
            refreshCacheStats()
            checkPreviousInstallation()
        } catch {
            service?.logger.log(.error, category: "host.lifecycle", action: "service.start.failed", "Host could not start", metadata: ["error": error.localizedDescription])
            service?.stop()
            service = nil
            running = false
            showError("Host could not start", error.localizedDescription)
        }
    }

    func refreshDevices() {
        let ids = Set(service?.network.peers.values.compactMap(\.remoteId) ?? [])
        do {
            remotes =
                try service?.store.remotes().compactMap { row in
                    guard let id = row["remote_id"]?.string, let name = row["display_name"]?.string else { return nil }
                    return PairedRemote(id: id, name: name, revoked: row["revoked_at_ms"]?.integer != nil)
                } ?? []
            connectedRemotes = remotes.filter { ids.contains($0.id) && !$0.revoked }
            if service?.invitation == nil { invitation = nil }
        } catch { showError("Could not read pairings", error.localizedDescription) }
    }

    func pair() {
        do { invitation = try service?.createInvitation() } catch {
            showError("Could not create pairing", error.localizedDescription)
        }
    }

    func revoke(_ remote: PairedRemote) {
        do {
            try service?.revoke(remote.id)
            refreshDevices()
            notify(remote.name + " was unpaired.")
        } catch { showError("Could not unpair Remote", error.localizedDescription) }
    }

    func setPolicy(_ enabled: Bool) {
        do {
            try service?.store.setPolicy(enabled)
            service?.queue.publish()
            notify(enabled ? "Cross-Remote edits allowed." : "Other Remotes' requests are protected.")
        } catch { showError("Could not change permissions", error.localizedDescription) }
    }

    func save() {
        guard !saving else { return }
        saving = true
        Task { @MainActor in
            defer { saving = false }
            do {
                try await service?.save(configuration)
                running = service?.network.ready ?? false
                scheduleUpdates()
                notify("Settings saved.")
            } catch {
                service?.logger.log(.error, category: "settings", action: "settings.save.failed", "Settings could not be saved", metadata: ["error": error.localizedDescription])
                running = service?.network.ready ?? false
                showError("Could not save settings", error.localizedDescription)
            }
        }
    }

    func refreshCacheStats() {
        guard let cache = service?.cache else {
            cacheStats = nil
            return
        }
        cacheStats = try? cache.stats()
    }

    func clearCache() {
        guard !clearingCache, let cache = service?.cache else { return }
        clearingCache = true
        Task { @MainActor in
            defer { clearingCache = false }
            do {
                try cache.removeAll()
                refreshCacheStats()
                notify("Local cache cleared.")
            } catch { showError("Cache could not be cleared", error.localizedDescription) }
        }
    }

    func control(_ kind: String) {
        guard !controlling, let service else { return }
        controlling = true
        Task { @MainActor in
            defer { controlling = false }
            do {
                try await service.queue.hostControl(kind)
            } catch { showError("Music did not confirm the action", error.localizedDescription) }
        }
    }

    func checkUpdates(automatic: Bool = false) {
        guard HostBuild.updatesEnabled else { return }
        guard !updateBusy, let updater else { return }
        if automatic && (configuration.updates.repository.isEmpty || !configuration.automaticUpdates) { return }
        updateBusy = true
        updateProgress = 0
        Task { @MainActor in
            defer { updateBusy = false }
            do {
                let message = try await updater.check(configuration: configuration.updates)
                stagedVersion = updater.staged?.1.version
                if automatic, stagedVersion != nil { installUpdate() } else { notify(message) }
            } catch {
                if !automatic { showError("Update could not be prepared", error.localizedDescription) }
            }
        }
    }

    func installUpdate() {
        guard HostBuild.updatesEnabled else { return }
        do {
            guard let service else { return }
            guard !service.queue.busy else {
                throw CadenzaError.failure("busy", "Wait for Music's current request to finish before updating.")
            }
            try service.queue.flushCredits()
            try updater?.install(configuration: configuration.updates, store: service.store)
        } catch { showError("Update could not be installed", error.localizedDescription) }
    }

    private func scheduleUpdates() {
        updateScheduler?.invalidate()
        guard HostBuild.updatesEnabled, configuration.automaticUpdates, !configuration.updates.repository.isEmpty else {
            return
        }
        let scheduler = NSBackgroundActivityScheduler(identifier: "app.cadence.host.updates")
        scheduler.interval = 86_400
        scheduler.tolerance = 3_600
        scheduler.repeats = true
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            Task { @MainActor in
                self?.checkUpdates(automatic: true)
                completion(.finished)
            }
        }
        updateScheduler = scheduler
        let checked = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
        if Date().timeIntervalSince(checked) >= 86_400 { checkUpdates(automatic: true) }
    }

    private func checkPreviousInstallation() {
        guard let directory = updater?.directory else { return }
        let url = directory.appendingPathComponent("install-result.json")
        guard let data = try? Data(contentsOf: url),
            let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        if result["success"] as? Bool == true {
            notify("Cadenza Host updated.")
        } else {
            showError(
                "Host update did not finish", result["message"] as? String ?? "The previous installation was preserved."
            )
        }
        try? FileManager.default.removeItem(at: url)
    }

    func notify(_ message: String) {
        toastTask?.cancel()
        toast = message
        AccessibilityNotification.Announcement(message).post()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    func finishOnboarding() -> Bool {
        guard running, service?.network.peers.values.contains(where: { $0.authenticated }) == true else {
            showError("Connect a Remote first", "Keep Cadenza Remote connected while finishing setup.")
            return false
        }
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
        onboardingComplete = true
        showingSetup = false
        return true
    }

    func showError(_ title: String, _ message: String) {
        prompt = HostPrompt(title: title, message: message)
    }
}
