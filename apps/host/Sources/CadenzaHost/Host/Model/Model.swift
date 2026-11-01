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
    var hostTransportPolicy: HostTransportPolicy = {
        guard let data = UserDefaults.standard.data(forKey: "hostTransportPolicy"),
            let value = try? JSONDecoder().decode(HostTransportPolicy.self, from: data)
        else { return HostTransportPolicy() }
        return value
    }()
    var remoteTransportPreferences: [String: TransportPreference] = {
        guard let data = UserDefaults.standard.data(forKey: "remoteTransportPreferences"),
            let value = try? JSONDecoder().decode([String: TransportPreference].self, from: data)
        else { return [:] }
        return value
    }()
    var remoteTransportManualPaths: [String: String] = {
        guard let data = UserDefaults.standard.data(forKey: "remoteTransportManualPaths"),
            let value = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return value
    }()
    var cacheStats: HostCacheStats?
    var clearingCache = false
    private var updater: HostUpdater?
    private var updateScheduler: NSBackgroundActivityScheduler?
    private var toastTask: Task<Void, Never>?
    private var watchdog: HostWatchdog?

    func saveTransportPolicy() {
        if let data = try? JSONEncoder().encode(hostTransportPolicy) {
            UserDefaults.standard.set(data, forKey: "hostTransportPolicy")
        }
        if let data = try? JSONEncoder().encode(remoteTransportPreferences) {
            UserDefaults.standard.set(data, forKey: "remoteTransportPreferences")
        }
        if let data = try? JSONEncoder().encode(remoteTransportManualPaths) {
            UserDefaults.standard.set(data, forKey: "remoteTransportManualPaths")
        }
        service?.transportPolicy = hostTransportPolicy
        service?.remoteTransportPreferences = remoteTransportPreferences
        service?.remoteTransportManualPaths = remoteTransportManualPaths
        service?.publishTransportStatus()
        notify("Transport policy saved.")
    }

    func start() async {
        guard !starting, !saving, !running else { return }
        starting = true
        defer { starting = false }
        if watchdog == nil { watchdog = try? HostWatchdog() }
        watchdog?.start()
        service?.stop()
        do {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            ).appendingPathComponent("Cadence Host", isDirectory: true)
            let service = try HostService(directory: directory, configuration: configuration)
            self.service = service
            service.transportPolicy = hostTransportPolicy
            service.remoteTransportPreferences = remoteTransportPreferences
            service.remoteTransportManualPaths = remoteTransportManualPaths
            if service.store.database.wasCreated {
                notify("Host storage was recreated. Pair your Remotes again.")
                service.logger.log(
                    .warning, category: "storage", action: "database.recreated", "Host database was recreated")
            }
            service.onSnapshot = { [weak self] value in self?.snapshot = value }
            service.hostUpdate = { [weak self] action in
                await self?.remoteHostUpdate(action)
                    ?? HostUpdateReply(state: "unavailable", version: nil, message: "Host updates are not available.")
            }
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
            service?.logger.log(
                .error, category: "host.lifecycle", action: "service.start.failed", "Host could not start",
                metadata: ["error": error.localizedDescription])
            service?.stop()
            service = nil
            running = false
            showError("Host could not start", error.localizedDescription)
        }
    }

    func markCleanShutdown() { watchdog?.markCleanShutdown() }

    func refreshDevices() {
        let connected: [String: SessionStatus?] = Dictionary(
            service?.network.peers.values.compactMap { peer in
                guard let remoteId = peer.remoteId else { return nil }
                return (remoteId, peer.status)
            } ?? [], uniquingKeysWith: { _, latest in latest })
        do {
            let rows = try service?.store.remotes() ?? []
            remotes = rows.compactMap { row in
                guard let id = row["remote_id"]?.string, let name = row["display_name"]?.string else {
                    return nil
                }
                return PairedRemote(
                    id: id, name: name, revoked: row["revoked_at_ms"]?.integer != nil,
                    status: connected[id] ?? nil)
            }
            connectedRemotes = remotes.filter { connected[$0.id] != nil && !$0.revoked }
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
                service?.logger.log(
                    .error, category: "settings", action: "settings.save.failed", "Settings could not be saved",
                    metadata: ["error": error.localizedDescription])
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
                if stagedVersion != nil {
                    installUpdate()
                } else if !automatic {
                    notify(message)
                }
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

    /// A paired Remote asked for a Host update. The Remote's own button is the confirmation, so this path
    /// never opens a Host alert or notification. Failures are returned to the Remote instead.
    func remoteHostUpdate(_ action: String) async -> HostUpdateReply {
        guard HostBuild.updatesEnabled, let updater, let service else {
            return HostUpdateReply(state: "unavailable", version: nil, message: "Host updates are not available.")
        }
        let updates = configuration.updates
        switch action {
        case "check":
            guard !updateBusy else {
                return HostUpdateReply(state: "failed", version: nil, message: "Cadenza Host is already checking.")
            }
            updateBusy = true
            defer { updateBusy = false }
            do {
                _ = try await updater.check(configuration: updates)
            } catch {
                return HostUpdateReply(state: "failed", version: nil, message: error.localizedDescription)
            }
            stagedVersion = updater.staged?.1.version
            if let version = stagedVersion {
                guard !service.queue.busy else {
                    return HostUpdateReply(
                        state: "failed", version: nil, message: "Wait for Music's current request to finish.")
                }
                do {
                    try service.queue.flushCredits()
                    _ = try updater.validateInstall(store: service.store)
                } catch {
                    return HostUpdateReply(state: "failed", version: nil, message: error.localizedDescription)
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    do {
                        try updater.install(configuration: updates, store: service.store)
                    } catch {
                        service.logger.log(
                            .error,
                            category: "update",
                            action: "install.failed",
                            error.localizedDescription
                        )
                    }
                }
                return HostUpdateReply(state: "installing", version: version, message: nil)
            }
            return HostUpdateReply(state: "current", version: nil, message: "Cadenza Host is up to date.")
        case "install":
            guard let version = updater.staged?.1.version else {
                return HostUpdateReply(state: "failed", version: nil, message: "Check for a Host update first.")
            }
            guard !service.queue.busy else {
                return HostUpdateReply(
                    state: "failed", version: nil, message: "Wait for Music's current request to finish.")
            }
            do {
                try service.queue.flushCredits()
                _ = try updater.validateInstall(store: service.store)
            } catch {
                return HostUpdateReply(state: "failed", version: nil, message: error.localizedDescription)
            }
            Task { @MainActor in
                // Let the reply leave the socket before this process exits.
                try? await Task.sleep(for: .milliseconds(500))
                do {
                    try updater.install(configuration: updates, store: service.store)
                } catch {
                    service.logger.log(.error, category: "update", action: "install.failed", error.localizedDescription)
                }
            }
            return HostUpdateReply(state: "installing", version: version, message: nil)
        default:
            return HostUpdateReply(state: "failed", version: nil, message: "Unknown Host update action.")
        }
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
        checkUpdates(automatic: true)
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
