import Foundation

// Wi-Fi Remote audio sockets arrive on the Web listener's `/cast/live?role=remote_audio`. Each one authenticates with its
// paired token before it can receive a stream, and it never carries Remote commands or stage traffic.
extension HostService {
    func configureRemoteAudio() {
        let hub = publishedState.remoteAudio
        hub.authenticate = { [weak self] auth in (try? self?.store.authenticate(auth)) ?? false }
        hub.log = { [weak self] level, action, message in
            self?.logger.log(level, category: "remote-audio", action: action, message)
        }
        hub.budget = { [weak self] in self?.publishedState.hostBudget ?? .unrestricted }
        hub.roomKey = { session in
            guard let output = AudioOutputs.defaultUID(), let agent = session.handshake?.userAgent else { return nil }
            return output + "|" + agent
        }
        hub.loadRoomOffsetUs = { [weak self] key in
            guard let store = self?.store else { return nil }
            return try? store.roomAcousticOffsetUs(profileKey: key)
        }
        hub.saveRoomOffsetUs = { [weak self] offset, key in
            guard let store = self?.store else { return }
            do {
                try store.saveRoomAcousticOffsetUs(offset, profileKey: key, measuredAtMs: wallMs())
            } catch {
                self?.logger.log(
                    .warning, category: "remote-audio", action: "calibration.save_failed",
                    "The room measurement could not be saved.")
            }
        }
        hub.clearRoomOffsetUs = { [weak self] key in try? self?.store.clearRoomProfile(profileKey: key) }
        hub.loadSetup = { RemoteAudioSetupStorage.load() }
        hub.saveSetup = { RemoteAudioSetupStorage.save($0) }
        hub.remoteName = { [weak self] id in (try? self?.store.remoteName(id)) ?? "Remote" }
        hub.restoreSetup()
        webRemote.onRemoteAudioSocket = { [weak self] socket in self?.publishedState.remoteAudio.attach(socket) }
    }
}
