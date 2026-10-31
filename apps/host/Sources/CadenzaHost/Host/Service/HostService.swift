import CryptoKit
import Foundation
import OSLog

@MainActor
final class HostService {
    let store: HostStore
    let music = MusicBridge()
    let catalog = Catalog()
    let cache: HostCache
    let artwork: ArtworkProvider
    let motion: MotionProvider
    let logger: HostLogger
    let lyrics: Lyrics
    let network = NetworkService()
    let pairingBootstrap = PairingBootstrap()
    let bluetooth = BluetoothPeripheral()
    let queue: QueueCoordinator
    private(set) var configuration: HostConfiguration
    var transportPolicy = HostTransportPolicy()
    var remoteTransportPreferences: [String: TransportPreference] = [:]
    var remoteTransportManualPaths: [String: String] = [:]
    private(set) var invitation: PairingInvitation?
    private var invitationDeadline: Int64 = 0
    private var invitationPinDeadline: Int64 = 0
    private var invitationPinAttempts = 0
    private var identity: TLSIdentity?
    private var polling: Task<Void, Never>?
    private var statusReporting: Task<Void, Never>?
    private var jobs: [String: Task<Void, Never>] = [:]
    private var lyricJob: Task<Void, Never>?
    private var lyricOccurrence: String?
    private var lyricDocument: LyricDocument?
    private var lastCreditSent: [String: Int64] = [:]
    private var acknowledgedCredits: [String: Int64] = [:]
    private var lastMaintenance: Int64 = 0
    private var receivedCommands: Set<String> = []
    private var transportDecisions: [String: EffectiveTransportDecision] = [:]
    private var transportDecisionAt: [String: Int64] = [:]
    private var observationEnabled = false
    private let observation = MusicObservation()
    private var listenerRecovery: Task<Void, Never>?
    private var serviceRunning = false
    private var lastPublished: HostSnapshot?
    private let latencyLog = Logger(subsystem: "app.cadence.host", category: "latency")
    var onSnapshot: ((HostSnapshot) -> Void)?
    var onDevicesChanged: (() -> Void)?
    var onIssue: ((String) -> Void)?
    var hostUpdate: ((String) async -> HostUpdateReply)?

    init(directory: URL, configuration: HostConfiguration) throws {
        self.configuration = configuration
        let store = try HostStore(directory: directory)
        self.store = store
        let logDatabase = try Database(
            url: directory.appendingPathComponent("database", isDirectory: true)
                .appendingPathComponent("logs.sqlite"), role: .logs)
        // Log batches are written in transactions, so the log file need not fsync on every commit.
        try logDatabase.execute("PRAGMA synchronous=NORMAL")
        self.logger = try HostLogger(database: logDatabase)
        music.logger = logger
        let cache = try HostCache(
            database: store.database,
            mediaDirectory: directory.appendingPathComponent("database", isDirectory: true)
                .appendingPathComponent("metadata", isDirectory: true),
            limitBytes: configuration.cacheLimitBytes)
        self.cache = cache
        self.artwork = ArtworkProvider(cache: cache)
        self.motion = MotionProvider(catalog: catalog, cache: cache)
        self.lyrics = Lyrics(cache: cache, providerEnabled: configuration.lyricsProviderEnabled)
        logger.log(.info, category: "host.lifecycle", action: "service.initialized", "Host service initialized")
        queue = QueueCoordinator(store: store, music: music, catalog: catalog)
        queue.logger = logger
        queue.currentArtwork = { [weak self] occurrenceId in
            try await self?.currentMusicArtwork(occurrenceId)
        }
        network.logger = logger
        queue.onSnapshot = { [weak self] snapshot in
            guard let self else { return }
            self.onSnapshot?(snapshot)
            if !self.network.peers.isEmpty {
                let unchanged = self.lastPublished.map { snapshot.permitsHeartbeat(comparedTo: $0) } ?? false
                if unchanged {
                    self.network.broadcast(Frame(type: "heartbeat", hostEpoch: snapshot.hostEpoch))
                    for peer in self.network.peers.values where peer.authenticated && !peer.supportsHeartbeat {
                        self.network.send(Frame(type: "state", snapshot: snapshot), to: peer)
                    }
                } else {
                    self.network.broadcast(Frame(type: "state", snapshot: snapshot))
                }
                self.lastPublished = snapshot
            }
            if snapshot.current?.occurrenceId != self.lyricDocument?.occurrenceId {
                self.lyricDocument = nil
                if self.lyricOccurrence != snapshot.current?.occurrenceId {
                    self.lyricJob?.cancel()
                    self.lyricJob = nil
                }
            }
        }
        queue.onCredits = { [weak self] in self?.deliverCredits() }
        queue.onIssue = { [weak self] message in self?.onIssue?(message) }
        queue.connectedRemoteIds = { [weak self] in
            Set(self?.network.peers.values.compactMap { $0.authenticated ? $0.remoteId : nil } ?? [])
        }
        network.onFrame = { [weak self] peer, frame in self?.receive(frame, from: peer) }
        network.onFailure = { [weak self] reason in self?.recoverListener(reason) }
        network.onIssue = { [weak self] message in self?.onIssue?(message) }
        pairingBootstrap.onRequest = { [weak self] secret in self?.bootstrapCertificate(for: secret) }
        network.onDisconnect = { [weak self] id in
            self?.lastCreditSent.removeValue(forKey: id)
            self?.acknowledgedCredits.removeValue(forKey: id)
            self?.transportDecisions.removeValue(forKey: id)
            self?.transportDecisionAt.removeValue(forKey: id)
            self?.settleCredits()
            self?.onDevicesChanged?()
        }
        bluetooth.onIssue = { [weak self] message in self?.onIssue?(message) }
        bluetooth.onEvent = { [weak self] action, message in
            self?.logger.log(.info, category: "bluetooth", action: action, message)
        }
        bluetooth.onSubscribe = { [weak self] centralID in
            guard let self else { return }
            self.network.acceptBluetooth(
                centralID: centralID,
                send: { [weak self] data in
                    guard let self else { return false }
                    return self.bluetooth.send(data, to: centralID, completion: { _ in })
                },
                cancel: {})
        }
        bluetooth.onReceive = { [weak self] centralID, data in
            self?.network.receiveBluetooth(data, from: centralID)
        }
        bluetooth.onUnsubscribe = { [weak self] centralID in
            self?.network.disconnectBluetooth(centralID)
        }
    }

    func start(observing: Bool? = nil) async throws {
        serviceRunning = true
        logger.log(.info, category: "host.lifecycle", action: "service.start", "Host service starting")
        if let observing { observationEnabled = observing }
        do {
            try store.beginEpoch()
            reauthorizeKeychainItemsIfNeeded()
            let identity = try await TLSIdentity.loadOrCreate(hostId: store.hostId)
            self.identity = identity
            try await network.start(
                identity: identity, port: configuration.port, name: configuration.name, hostId: store.hostId)
            try await pairingBootstrap.start(controlPort: configuration.port)
            bluetooth.start()
            startStatusReporting()
            await catalog.configure(storefront: configuration.storefront)
            if observationEnabled { startObservation() }
        } catch {
            serviceRunning = false
            pairingBootstrap.stop()
            network.stop()
            throw error
        }
    }

    func startObservation() {
        observationEnabled = true
        observation.start { [weak self] in
            guard let self, self.observationEnabled else { return }
            await self.queue.refresh()
        }
        polling?.cancel()
        statusReporting?.cancel()
        statusReporting = nil
        polling = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.queue.refresh()
                if !self.queue.busy && monotonicMs() - self.lastMaintenance > 300_000 {
                    do { try self.store.database.maintain() } catch {
                        self.onIssue?("Database maintenance failed: " + error.localizedDescription)
                    }
                    self.lastMaintenance = monotonicMs()
                }
                let playing = self.queue.isPlaying
                try? await Task.sleep(
                    for: .milliseconds(playing ? 1_000 : (self.network.peers.isEmpty ? 10_000 : 2_000)))
            }
        }
    }

    /// Items keep the access list of the signature that created them, so an older signature makes macOS ask
    /// for every item after each update. Rebuild them under the running signature once. Bump the key when the
    /// signing identity changes. A denied prompt leaves the items as they are and retries on the next launch.
    private func reauthorizeKeychainItemsIfNeeded() {
        let key = "keychainAccess.reauthorized.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        do {
            var accounts = ["catalog.public-token", "tls.\(store.hostId)"]
            accounts += try store.database.query("SELECT credential_reference FROM paired_remotes").compactMap {
                $0["credential_reference"]?.string
            }
            for account in accounts { try SecureStore.reauthorize(account) }
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            logger.log(
                .warning, category: "security", action: "keychain.reauthorize.deferred",
                "Keychain access will be updated after the next approval.")
        }
    }

    private func settleCredits() {
        do { try queue.flushCredits() } catch { onIssue?(error.localizedDescription) }
    }

    func stop() {
        serviceRunning = false
        logger.log(.info, category: "host.lifecycle", action: "service.stop", "Host service stopping")
        settleCredits()
        polling?.cancel()
        observation.stop()
        listenerRecovery?.cancel()
        listenerRecovery = nil
        lyricJob?.cancel()
        lyricJob = nil
        lyricOccurrence = nil
        lyricDocument = nil
        for job in jobs.values { job.cancel() }
        jobs.removeAll()
        network.stop()
        pairingBootstrap.stop()
        bluetooth.stop()
        logger.flush()
    }

    private func startStatusReporting() {
        statusReporting?.cancel()
        statusReporting = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, !Task.isCancelled else { return }
                for peer in self.network.peers.values where peer.authenticated {
                    self.network.send(
                        Frame(type: "session.status", status: self.hostStatus(for: peer)), to: peer)
                }
            }
        }
    }

    private func recoverListener(_ reason: String?) {
        guard serviceRunning, listenerRecovery == nil, let identity else { return }
        listenerRecovery = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.listenerRecovery = nil }
            var reported = false
            while !Task.isCancelled {
                for seconds in [1, 2, 4, 8, 16, 30] {
                    do {
                        try await Task.sleep(for: .seconds(seconds))
                        try Task.checkCancellation()
                        try await self.network.start(
                            identity: identity, port: self.configuration.port, name: self.configuration.name,
                            hostId: self.store.hostId)
                        try await self.pairingBootstrap.start(controlPort: self.configuration.port)
                        self.onDevicesChanged?()
                        return
                    } catch is CancellationError { return } catch { continue }
                }
                if !reported {
                    reported = true
                    let cause = reason.map { " (" + $0 + ")" } ?? ""
                    self.onIssue?(
                        "The local listener is still unavailable" + cause
                            + ". Cadenza Host will keep retrying; check Local Network permission and the selected port."
                    )
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func save(_ configuration: HostConfiguration) async throws {
        guard !queue.busy else {
            throw CadenzaError.failure("busy", "Wait for the current Music action before changing network settings.")
        }
        guard configuration.isUsable else {
            throw CadenzaError.failure(
                "configuration", "Enter a two-letter storefront, a device name, and a port from 1024 to 65535.")
        }
        try configuration.save()
        self.configuration = configuration
        stop()
        try await start()
    }

    func createInvitation() throws -> PairingInvitation {
        guard let identity else { throw CadenzaError.failure("network", "Host is still starting.") }
        guard pairingBootstrap.ready else {
            throw CadenzaError.failure("network", "Pairing is still starting. Try again in a moment.")
        }
        let address =
            configuration.advertisedAddress.isEmpty ? LANAddresses.all().first : configuration.advertisedAddress
        guard let address else {
            throw CadenzaError.failure("network", "Connect Cadenza Host to your local network first.")
        }
        let invitation = PairingInvitation(
            host: address, port: Int(configuration.port), fingerprint: identity.fingerprint,
            certificateDerBase64: identity.certificateDerBase64,
            secret: try SecureStore.randomToken(), hostName: configuration.name,
            pin: String(format: "%04d", Int.random(in: 0...9_999))
        )
        self.invitation = invitation
        invitationDeadline = monotonicMs() + 300_000
        invitationPinDeadline = monotonicMs() + 7_000
        invitationPinAttempts = 0
        return invitation
    }

    private func bootstrapCertificate(for secret: Data) -> Data? {
        guard let invitation, let identity,
            monotonicMs() < invitationDeadline,
            SecureStore.equal(String(decoding: secret, as: UTF8.self), invitation.secret)
        else { return nil }
        return Data(base64Encoded: identity.certificateDerBase64)
    }

    func revoke(_ remoteId: String) throws {
        try store.revoke(remoteId)
        network.revoke(remoteId)
        onDevicesChanged?()
    }

    private func receive(_ frame: Frame, from peer: NetworkService.Peer) {
        let receivedAt = monotonicMs()
        // Frames are counted per minute rather than written one by one. Each action a frame requests is logged in full.
        logger.count(frame.type)
        do {
            if !peer.authenticated {
                try authenticate(frame, peer: peer)
                return
            }
            guard let actor = peer.remoteId,
                try store.database.query(
                    "SELECT remote_id FROM paired_remotes WHERE remote_id=? AND revoked_at_ms IS NULL", [.text(actor)]
                ).first != nil
            else { throw CadenzaError.failure("revoked", "This Remote is no longer paired.") }
            switch frame.type {
            case "host.update":
                handleHostUpdate(frame, peer: peer)
            case "remote.configure":
                guard let name = frame.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                    (1...80).contains(name.count),
                    !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
                else {
                    throw CadenzaError.failure(
                        "invalid_command", "Use a Remote name from 1 to 80 characters without control characters.")
                }
                try store.database.run(
                    "UPDATE paired_remotes SET display_name=? WHERE remote_id=?", [.text(name), .text(actor)])
                peer.supportsHeartbeat = frame.heartbeat == true
                network.send(Frame(type: "remote.configured", requestId: frame.requestId), to: peer)
                queue.publish()
                onDevicesChanged?()
            case "session.status":
                guard let status = frame.status, status.device == "remote" else {
                    throw CadenzaError.failure("invalid_command", "Invalid Remote status.")
                }
                peer.status = status
                peer.effectiveDecision = self.decideTransport(
                    peer: peer, paths: status.paths, remotePreference: status.preference,
                    remoteConstraints: status.constraints)
                network.send(Frame(type: "session.status", status: self.hostStatus(for: peer)), to: peer)
                onDevicesChanged?()
            case "transport.configure":
                guard let policy = frame.transport,
                    ["lan_only", "ble_only", "hybrid"].contains(policy.mode),
                    ["deterministic", "opportunistic"].contains(policy.selection)
                else { throw CadenzaError.failure("invalid_command", "Invalid transport policy.") }
                peer.transportPolicy = policy
                network.send(
                    Frame(type: "transport.configured", requestId: frame.requestId, transport: policy), to: peer)
            case "log.report": try recordRemoteLogs(frame, peer: peer)
            case "artwork.get": loadArtwork(peer: peer, requestId: frame.requestId, url: frame.artworkUrl)
            case "clock": try clock(frame, peer: peer)
            case "state.get": network.send(Frame(type: "state", snapshot: try queue.snapshot()), to: peer)
            case "analytics.ack": try acknowledge(frame, peer: peer, actor: actor)
            case "command": command(frame, peer: peer, actor: actor, receivedAt: receivedAt)
            case "command.status":
                let queued =
                    receivedCommands.contains(actor + (frame.commandId ?? ""))
                    || queue.commandQueued(frame.commandId ?? "", actor: actor)
                network.send(try queue.journal.status(frame, actor: actor, queued: queued), to: peer)
            case "search", "search.suggest", "song.prepare": operation(frame, peer: peer)
            case "operation.cancel":
                if let id = frame.requestId { jobs.removeValue(forKey: peer.id + id)?.cancel() }
            case "lyrics.get": loadLyrics(peer: peer, requestId: frame.requestId)
            case "motion.get": loadMotion(peer: peer, requestId: frame.requestId, occurrenceId: frame.occurrenceId)
            default: throw CadenzaError.failure("invalid_command", "Unsupported message.")
            }
        } catch { fail(error, request: frame, peer: peer) }
    }

    private func authenticate(_ frame: Frame, peer: NetworkService.Peer) throws {
        var token: String?
        let remoteId: String
        var cursor: Int64 = 0
        if frame.type == "pair", let pair = frame.pair, let invitation,
            monotonicMs() < invitationDeadline
        {
            let now = monotonicMs()
            let secretValid = pair.secret.map { SecureStore.equal($0, invitation.secret) } ?? false
            let pinValid =
                !invitation.pin.isEmpty && invitationPinAttempts < 3 && now < invitationPinDeadline
                && pair.pin == invitation.pin
            guard secretValid || pinValid else {
                if pair.pin != nil { invitationPinAttempts += 1 }
                throw CadenzaError.failure("authentication", "The pairing PIN is invalid or expired.")
            }
            let name = pair.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (1...80).contains(name.count) else {
                throw CadenzaError.failure("invalid_command", "Enter a Remote name from 1 to 80 characters.")
            }
            (remoteId, token) = try store.pair(name: name)
            logger.log(
                .info, category: "network", action: "remote.paired", "Remote paired with this Host",
                remoteVersion: pair.remoteVersion, metadata: ["remote_id": remoteId, "name": name])
            peer.supportsHeartbeat = pair.heartbeat == true
            peer.remoteVersion = pair.remoteVersion
            self.invitation = nil
            invitationPinDeadline = 0
            invitationPinAttempts = 3
        } else if frame.type == "hello", let auth = frame.auth, try store.authenticate(auth) {
            remoteId = auth.remoteId
            peer.remoteVersion = auth.remoteVersion
            peer.supportsHeartbeat = auth.heartbeat == true
            if let requestedName = auth.name {
                let name = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard (1...80).contains(name.count),
                    !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
                else {
                    throw CadenzaError.failure(
                        "invalid_command", "Use a Remote name from 1 to 80 characters without control characters.")
                }
                try store.database.run(
                    "UPDATE paired_remotes SET display_name=? WHERE remote_id=?", [.text(name), .text(remoteId)])
            }
            cursor = auth.lastCreditSequence
            try store.acknowledge(remoteId, through: cursor)
        } else {
            throw CadenzaError.failure("authentication", "Pairing expired or the device credential is invalid.")
        }
        // Playing time before this Remote joined belongs to the Remotes already connected.
        settleCredits()
        peer.remoteId = remoteId
        peer.authenticated = true
        logger.log(
            .info, category: "network", action: "remote.authenticated", "Remote connected",
            remoteVersion: peer.remoteVersion, metadata: ["remote_id": remoteId, "method": frame.type])
        lastCreditSent[peer.id] = cursor
        acknowledgedCredits[peer.id] = cursor
        let welcomeAddress =
            configuration.advertisedAddress.isEmpty ? LANAddresses.all().first : configuration.advertisedAddress
        var welcome = Welcome(
            hostId: store.hostId, hostName: configuration.name, hostEpoch: store.epoch,
            remoteId: remoteId, token: token, hostAddress: welcomeAddress,
            hostPort: Int(configuration.port), hostFingerprint: identity?.fingerprint,
            hostCertificateDerBase64: identity?.certificateDerBase64,
            hostTimeMs: monotonicMs(), updates: configuration.updates
        )
        if !configuration.lyricsProviderEnabled { welcome.capabilities.removeAll { $0 == "lyrics.lrclib" } }
        if !HostBuild.updatesEnabled { welcome.capabilities.removeAll { $0 == "host.update" } }
        network.send(Frame(type: "welcome", requestId: frame.requestId, welcome: welcome), to: peer)
        network.send(Frame(type: "session.status", status: hostStatus(for: peer)), to: peer)
        network.send(Frame(type: "state", snapshot: try queue.snapshot()), to: peer)
        Task { @MainActor [weak self] in await self?.queue.refresh() }
        sendCredits(peer)
        onDevicesChanged?()
    }

    private func handleHostUpdate(_ frame: Frame, peer: NetworkService.Peer) {
        guard let action = frame.updateAction, let requestId = frame.requestId else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let reply =
                await self.hostUpdate?(action)
                ?? HostUpdateReply(state: "unavailable", version: nil, message: "Host updates are not available.")
            var status = Frame(type: "host.update.status", requestId: requestId)
            status.updateState = reply.state
            status.updateVersion = reply.version
            status.message = reply.message
            self.network.send(status, to: peer)
        }
    }

    func publishTransportStatus() {
        for peer in network.peers.values where peer.authenticated {
            network.send(Frame(type: "session.status", status: hostStatus(for: peer)), to: peer)
        }
    }

    private func hostStatus(for peer: NetworkService.Peer? = nil) -> SessionStatus {
        let remotePeers =
            peer.flatMap { target in
                network.peers.values.filter { $0.remoteId == target.remoteId && $0.authenticated }
            } ?? []
        let hasLan = remotePeers.contains { $0.transport == "lan" }
        let hasBle = remotePeers.contains { $0.transport == "ble" }
        let paths = [
            TransportPathStatus(
                transport: "lan",
                state: hasLan ? "connected" : "disconnected",
                rssiDbm: nil,
                rttMs: nil,
                lossPercent: nil,
                throughputKbps: nil,
                backlogBytes: nil),
            TransportPathStatus(
                transport: "ble",
                state: hasBle ? "connected" : "disconnected",
                rssiDbm: nil,
                rttMs: nil,
                lossPercent: nil,
                throughputKbps: nil,
                backlogBytes: nil),
        ]
        let hostPolicy = peer.map(policy(for:)) ?? transportPolicy
        let preference = peer?.status?.preference
        let decision =
            peer.map {
                decideTransport(
                    peer: $0,
                    paths: paths,
                    remotePreference: preference,
                    remoteConstraints: $0.status?.constraints
                )
            }
            ?? TransportNegotiator.decide(
                host: hostPolicy,
                remote: nil,
                remotePreference: preference,
                paths: paths)
        return SessionStatus(
            reportedAtMs: monotonicMs(),
            device: "host",
            power: nil,
            resources: nil,
            paths: paths,
            effective: decision,
            preference: hostPolicy.preference,
            constraints: hostPolicy.constraints)
    }

    private func policy(for peer: NetworkService.Peer) -> HostTransportPolicy {
        var policy = transportPolicy
        if let remoteId = peer.remoteId, let override = remoteTransportPreferences[remoteId] {
            policy.preference = override
        }
        if let remoteId = peer.remoteId, let manual = remoteTransportManualPaths[remoteId] {
            policy.manualPath = manual == "auto" ? nil : manual
        }
        return policy
    }

    private func decideTransport(
        peer: NetworkService.Peer,
        paths: [TransportPathStatus],
        remotePreference: TransportPreference?,
        remoteConstraints: TransportConstraints?
    ) -> EffectiveTransportDecision {
        let policy = policy(for: peer)
        let candidate = TransportNegotiator.decide(
            host: policy, remote: peer.transportPolicy, remotePreference: remotePreference,
            remoteConstraints: remoteConstraints, paths: paths)
        let key = peer.remoteId ?? peer.id
        let now = monotonicMs()
        if let previous = transportDecisions[key], previous.selected != candidate.selected,
            now - (transportDecisionAt[key] ?? 0) < policy.minimumDwellMs,
            let selected = previous.selected,
            paths.contains(where: { $0.transport == selected && $0.state == "connected" })
        {
            return previous
        }
        transportDecisions[key] = candidate
        transportDecisionAt[key] = now
        return candidate
    }

    private func clock(_ frame: Frame, peer: NetworkService.Peer) throws {
        guard var sample = frame.clock, sample.sentAtRemoteMs >= 0 else {
            throw CadenzaError.failure("invalid_command", "Invalid clock sample.")
        }
        sample.receivedAtHostMs = monotonicMs()
        sample.sentAtHostMs = monotonicMs()
        network.send(Frame(type: "clock", requestId: frame.requestId, clock: sample), to: peer)
    }

    private func command(_ frame: Frame, peer: NetworkService.Peer, actor: String, receivedAt: Int64) {
        let reservation = actor + (frame.commandId ?? "")
        logCommand(frame, peer: peer)
        receivedCommands.insert(reservation)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.receivedCommands.remove(reservation) }
            do {
                let startedAt = monotonicMs()
                let result = try await self.queue.execute(frame, actor: actor)
                let completedAt = monotonicMs()
                let latencyMessage =
                    "command_id=\(frame.commandId ?? "unknown")"
                    + " received=\(receivedAt)"
                    + " started=\(startedAt)"
                    + " completed=\(completedAt)"
                self.latencyLog.debug("\(latencyMessage, privacy: .public)")
                self.logCommandResult(result, request: frame, peer: peer, receivedAt: receivedAt)
                self.network.send(result, to: peer)
            } catch { self.fail(error, request: frame, peer: peer) }
        }
    }

    private func operation(_ frame: Frame, peer: NetworkService.Peer) {
        guard let requestId = frame.requestId, jobs.count < 16 else {
            fail(CadenzaError.failure("busy", "Too many searches are running."), request: frame, peer: peer)
            return
        }
        let key = peer.id + requestId
        jobs[key]?.cancel()
        network.send(Frame(type: "operation.started", requestId: requestId), to: peer)
        jobs[key] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.jobs.removeValue(forKey: key) }
            let startedAt = monotonicMs()
            do {
                if frame.type == "search.suggest" {
                    // Suggestions are counted rather than logged one by one: they arrive as the user types.
                    let suggestions = try await self.catalog.suggest(frame.query ?? "")
                    try Task.checkCancellation()
                    self.queue.remember(suggestions.songs)
                    var reply = Frame(type: "search.suggestions", requestId: requestId, songs: suggestions.songs)
                    reply.terms = suggestions.terms
                    self.network.send(reply, to: peer)
                    self.logger.count("search.suggest")
                } else if frame.type == "search" {
                    let songs: [Song]
                    if frame.scope == "library" {
                        songs = try await self.music.librarySearch(frame.query ?? "")
                    } else {
                        songs = try await self.catalog.search(frame.query ?? "")
                    }
                    try Task.checkCancellation()
                    self.logger.log(
                        .info, category: "catalog", action: "search.completed", "Search returned \(songs.count) songs",
                        remoteVersion: peer.remoteVersion,
                        metadata: [
                            "scope": frame.scope ?? "catalog", "query": String((frame.query ?? "").prefix(80)),
                            "count": String(songs.count), "ms": String(monotonicMs() - startedAt),
                            "remote_id": peer.remoteId ?? "",
                        ])
                    self.queue.remember(songs)
                    self.network.send(Frame(type: "search.result", requestId: requestId, songs: songs), to: peer)
                } else {
                    guard let song = frame.song, Wire.validate(song) else {
                        throw CadenzaError.failure("invalid_command", "Invalid song identity.")
                    }
                    try await self.queue.prepare(song, metadata: frame.songMetadata)
                    try Task.checkCancellation()
                    self.network.send(Frame(type: "song.ready", requestId: requestId, song: song), to: peer)
                }
            } catch {
                if !Task.isCancelled { self.fail(error, request: frame, peer: peer) }
            }
        }
    }

    private func loadLyrics(peer: NetworkService.Peer, requestId: String?) {
        do {
            guard let current = try queue.snapshot().current else {
                throw CadenzaError.failure("lyrics_unavailable", "Play a song first.")
            }
            if let document = lyricDocument, document.occurrenceId == current.occurrenceId {
                network.send(Frame(type: "lyrics", requestId: requestId, lyrics: document), to: peer)
                if document.issue == nil { return }
            }
            network.send(Frame(type: "operation.started", requestId: requestId), to: peer)
            if lyricJob != nil, lyricOccurrence == current.occurrenceId { return }
            lyricJob?.cancel()
            lyricOccurrence = current.occurrenceId
            lyricJob = Task { @MainActor [weak self] in
                guard let self else { return }
                defer { if self.lyricOccurrence == current.occurrenceId { self.lyricJob = nil } }
                do {
                    var document: LyricDocument?
                    var lastError: Error?
                    for attempt in 0..<6 {
                        do {
                            // Disk and provider caches do not require Music's
                            // Accessibility permission. Check them first so a Host
                            // restart can restore lyrics immediately.
                            document = try await self.lyrics.document(
                                song: current.song, occurrence: current.occurrenceId)
                            break
                        } catch let error as CadenzaError where error.code == "lyrics_unavailable" {
                            lastError = error
                            guard attempt < 5, self.music.accessibility.permitted else { break }
                            // Music may not have written its local TTML cache yet.
                            // Prime it and retry with a bounded backoff instead of
                            // turning a transient read into a permission warning.
                            try? await self.queue.primeLyrics(occurrence: current.occurrenceId)
                            try await Task.sleep(for: .milliseconds(1_000 << min(attempt, 3)))
                        }
                    }
                    guard let document else {
                        if let lastError { throw lastError }
                        throw CadenzaError.failure(
                            "lyrics_unavailable", "Lyrics are unavailable. Try again from the Lyrics pane.")
                    }
                    guard !Task.isCancelled, try self.queue.snapshot().current?.occurrenceId == document.occurrenceId
                    else { return }
                    self.lyricDocument = document
                    self.logger.log(
                        .info, category: "lyrics", action: "lyrics.loaded",
                        "Lyrics ready with \(document.lines.count) lines",
                        metadata: [
                            "occurrence_id": current.occurrenceId, "source": document.source,
                            "translation": document.translationSource,
                        ])
                    self.network.broadcast(Frame(type: "lyrics", lyrics: document))
                    let translated = await self.lyrics.english(document, song: current.song)
                    guard !Task.isCancelled, try self.queue.snapshot().current?.occurrenceId == translated.occurrenceId
                    else { return }
                    self.lyricDocument = translated
                    if translated.revision != document.revision {
                        self.network.broadcast(Frame(type: "lyrics", lyrics: translated))
                    }
                } catch {
                    if !Task.isCancelled {
                        self.logger.log(
                            .warning, category: "lyrics", action: "lyrics.unavailable", error.localizedDescription,
                            metadata: ["occurrence_id": current.occurrenceId])
                        var unavailable = Frame(type: "lyrics.unavailable")
                        unavailable.occurrenceId = current.occurrenceId
                        unavailable.message = error.localizedDescription
                        self.network.broadcast(unavailable)
                    }
                }
            }
        } catch { fail(error, request: Frame(type: "lyrics.get", requestId: requestId), peer: peer) }
    }

    // Music's artwork for the playing track. The caller checks that the occurrence is still current.
    private func currentMusicArtwork(_ occurrenceId: String) async throws -> String? {
        guard let data = try await music.currentArtwork() else { return nil }
        return try artwork.storeMusicArtwork(data, occurrenceId: occurrenceId)
    }

    private func loadArtwork(peer: NetworkService.Peer, requestId: String?, url: String?) {
        guard let requestId, let url else {
            fail(
                CadenzaError.failure("artwork_unavailable", "Artwork request is invalid."),
                request: Frame(type: "artwork.get", requestId: requestId), peer: peer)
            return
        }
        // A refusal is answered with artwork.unavailable, which releases the Remote's pending request. An error
        // frame would leave that request pending, so the artwork would never be asked for again.
        guard ArtworkProvider.isServableURL(url), jobs.count < 16 else {
            var refusal = Frame(type: "artwork.unavailable", requestId: requestId)
            refusal.artworkUrl = url
            refusal.message = "Artwork is not available from Cadenza Host right now."
            network.send(refusal, to: peer)
            return
        }
        let key = peer.id + requestId
        jobs[key]?.cancel()
        network.send(Frame(type: "operation.started", requestId: requestId), to: peer)
        jobs[key] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.jobs.removeValue(forKey: key) }
            do {
                guard let data = try await self.artwork.data(for: url) else {
                    throw CadenzaError.failure("artwork_unavailable", "Artwork is unavailable.")
                }
                var frame = Frame(type: "artwork", requestId: requestId)
                frame.artworkUrl = url
                frame.artworkDataBase64 = data.base64EncodedString()
                self.network.send(frame, to: peer)
            } catch {
                if !Task.isCancelled {
                    var frame = Frame(type: "artwork.unavailable", requestId: requestId)
                    frame.artworkUrl = url
                    frame.message = error.localizedDescription
                    self.network.send(frame, to: peer)
                }
            }
        }
    }

    // Animated album art reaches the Remote as bounded chunks of one cached file, with a digest the Remote checks before
    // playing it. A song change or a refusal is answered with motion.unavailable, which releases the Remote's request.
    private func loadMotion(peer: NetworkService.Peer, requestId: String?, occurrenceId: String?) {
        guard let requestId, let occurrenceId else {
            fail(
                CadenzaError.failure("motion_unavailable", "Motion request is invalid."),
                request: Frame(type: "motion.get", requestId: requestId), peer: peer)
            return
        }
        let key = peer.id + requestId
        jobs[key]?.cancel()
        jobs[key] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.jobs.removeValue(forKey: key) }
            var unavailable = Frame(type: "motion.unavailable", requestId: requestId)
            unavailable.occurrenceId = occurrenceId
            do {
                guard let current = try self.queue.snapshot().current, current.occurrenceId == occurrenceId,
                    let video = try await self.motion.video(album: current.song.album, artist: current.song.artist)
                else {
                    self.network.send(unavailable, to: peer)
                    return
                }
                // The song may change during the download. The newer occurrence has its own request.
                guard try self.queue.snapshot().current?.occurrenceId == occurrenceId else { return }
                self.sendMotion(video, requestId: requestId, occurrenceId: occurrenceId, to: peer)
            } catch {
                if !Task.isCancelled {
                    unavailable.message = error.localizedDescription
                    self.network.send(unavailable, to: peer)
                }
            }
        }
    }

    private static let motionChunkBytes = 480 * 1_024

    private func sendMotion(_ video: Data, requestId: String, occurrenceId: String, to peer: NetworkService.Peer) {
        let count = (video.count + Self.motionChunkBytes - 1) / Self.motionChunkBytes
        let digest = SHA256.hash(data: video).map { String(format: "%02x", $0) }.joined()
        for index in 0..<count {
            let start = index * Self.motionChunkBytes
            var frame = Frame(type: "motion.chunk", requestId: requestId)
            frame.occurrenceId = occurrenceId
            frame.chunkIndex = index
            frame.chunkCount = count
            frame.totalBytes = video.count
            frame.sha256 = digest
            frame.dataBase64 = video[start..<min(start + Self.motionChunkBytes, video.count)].base64EncodedString()
            network.send(frame, to: peer)
        }
        logger.log(
            .info, category: "motion", action: "motion.sent", "Motion artwork sent in \(count) chunks",
            metadata: ["occurrence_id": occurrenceId, "bytes": String(video.count)])
    }

    private func acknowledge(_ frame: Frame, peer: NetworkService.Peer, actor: String) throws {
        guard let sequence = frame.sequence, sequence >= (acknowledgedCredits[peer.id] ?? 0),
            sequence <= (lastCreditSent[peer.id] ?? 0)
        else {
            throw CadenzaError.failure("invalid_command", "Invalid analytics acknowledgment.")
        }
        try store.acknowledge(actor, through: sequence)
        acknowledgedCredits[peer.id] = sequence
        sendCredits(peer)
    }

    private func deliverCredits() {
        for peer in network.peers.values where peer.authenticated { sendCredits(peer) }
    }

    private func sendCredits(_ peer: NetworkService.Peer) {
        guard let actor = peer.remoteId else { return }
        let sent = lastCreditSent[peer.id] ?? 0
        let acknowledged = acknowledgedCredits[peer.id] ?? 0
        guard sent - acknowledged < 8 else { return }
        do {
            let available = 8 - Int(sent - acknowledged)
            for frame in try store.credits(actor, after: sent).prefix(available) {
                network.send(frame, to: peer)
                lastCreditSent[peer.id] = frame.sequence
            }
        } catch { onIssue?(error.localizedDescription) }
    }

    // Every command field a debugging session needs, without the song's full metadata.
    private func commandMetadata(_ frame: Frame, peer: NetworkService.Peer) -> [String: String] {
        var metadata = [
            "command_id": frame.commandId ?? "", "remote_id": peer.remoteId ?? "",
            "kind": frame.action?.kind ?? "", "expected_revision": frame.expectedRevision.map(String.init) ?? "",
        ]
        if let song = frame.action?.song { metadata["song"] = song.source + ":" + song.id }
        if let entry = frame.action?.entryId { metadata["entry_id"] = entry }
        if let occurrence = frame.action?.occurrenceId { metadata["occurrence_id"] = occurrence }
        if let position = frame.action?.positionMs { metadata["position_ms"] = String(position) }
        if let percent = frame.action?.percent { metadata["percent"] = String(percent) }
        return metadata
    }

    private func logCommand(_ frame: Frame, peer: NetworkService.Peer) {
        logger.log(
            .info, category: "command", action: "command.received",
            "Remote requested \(frame.action?.kind ?? "a command")", remoteVersion: peer.remoteVersion,
            metadata: commandMetadata(frame, peer: peer))
    }

    private func logCommandResult(_ result: Frame, request: Frame, peer: NetworkService.Peer, receivedAt: Int64) {
        let outcome = result.outcome ?? "unknown"
        var metadata = commandMetadata(request, peer: peer)
        metadata["outcome"] = outcome
        metadata["error_code"] = result.errorCode ?? ""
        metadata["ms"] = String(monotonicMs() - receivedAt)
        logger.log(
            outcome == "applied" ? .info : .warning, category: "command", action: "command.result",
            "Command \(outcome)", remoteVersion: peer.remoteVersion, metadata: metadata)
    }

    // Remote entries keep the Remote's identity, so one debugging session can follow both sides of a request.
    private func recordRemoteLogs(_ frame: Frame, peer: NetworkService.Peer) throws {
        let entries =
            frame.logEntries
            ?? frame.logAction.map {
                [LogReportEntry(level: frame.logLevel ?? "", action: $0, message: frame.logMessage ?? "")]
            } ?? []
        guard !entries.isEmpty else { throw CadenzaError.failure("invalid_command", "Invalid log report.") }
        for entry in entries {
            guard let level = HostLogLevel(rawValue: entry.level) else { continue }
            logger.log(
                level, category: "remote", action: entry.action, entry.message, source: "remote",
                remoteVersion: peer.remoteVersion, metadata: ["remote_id": peer.remoteId ?? ""])
        }
    }

    private func fail(_ error: Error, request: Frame, peer: NetworkService.Peer) {
        let code = (error as? CadenzaError)?.code ?? "unavailable"
        logger.log(
            .warning, category: "protocol", action: "request.failed", error.localizedDescription,
            remoteVersion: peer.remoteVersion,
            metadata: [
                "type": request.type, "code": code, "remote_id": peer.remoteId ?? "",
                "command_id": request.commandId ?? "", "request_id": request.requestId ?? "",
            ])
        if request.type == "command" {
            do {
                let phase = try store.database.query(
                    "SELECT phase FROM command_intents WHERE remote_id=? AND command_id=?",
                    [.text(peer.remoteId ?? ""), .text(request.commandId ?? "")]
                ).first?["phase"]?.string
                let failure = CommandFailure(dispatched: phase == "dispatched", code: code)
                let result = try queue.journal.result(
                    request, outcome: failure.outcome, code: failure.code, message: error.localizedDescription
                )
                network.send(result, to: peer)
            } catch { network.disconnect(peer.id) }
        } else {
            network.send(
                Frame(
                    type: "error", requestId: request.requestId, errorCode: code, message: error.localizedDescription),
                to: peer)
        }
    }
}
