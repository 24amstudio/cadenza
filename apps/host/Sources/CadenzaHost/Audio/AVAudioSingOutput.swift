import AVFAudio
import Foundation

/// Plays processed buffers through the user's current macOS output device.
final class AVAudioSingOutput: SingOutputSink, @unchecked Sendable {
    // Created when Sing first plays, so a Host that never uses Sing holds no audio engine.
    private lazy var engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var attached = false
    private var started = false
    private var activeFormat: SingAudioFormat?
    private var rebuildScheduled = false
    private var configurationObserver: NSObjectProtocol?
    var onFailure: (@Sendable (String) -> Void)?

    private func observeConfigurationChanges() {
        guard configurationObserver == nil else { return }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.started, !self.rebuildScheduled else { return }
            self.rebuildScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.rebuildScheduled = false
                self?.rebuildAfterConfigurationChange()
            }
        }
    }

    deinit {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
    }

    func start(format: SingAudioFormat) throws {
        let audioFormat = try makeFormat(format)
        activeFormat = format
        observeConfigurationChanges()
        if !attached {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: audioFormat)
            attached = true
        }
        if !started {
            try engine.start()
            started = true
        }
        player.play()
    }

    func enqueue(_ buffer: SingAudioBuffer) {
        guard started else { return }
        guard engine.isRunning else {
            started = false
            onFailure?("The Sing audio output stopped unexpectedly.")
            return
        }
        player.scheduleBuffer(buffer.samples)
    }

    /// Schedules a block to start at a mach absolute time. The player holds it until then, so the start is sample-accurate.
    func enqueue(_ buffer: SingAudioBuffer, hostTime: UInt64) {
        guard started, engine.isRunning else { return }
        player.scheduleBuffer(buffer.samples, at: AVAudioTime(hostTime: hostTime), options: [], completionHandler: nil)
    }

    func flush() {
        guard started else { return }
        // AVAudioPlayerNode.stop drops every scheduled buffer; play() resumes the node for new audio.
        player.stop()
        player.play()
    }

    func stop() {
        // Nothing was ever started, so there is no engine to stop and none is created for this.
        guard configurationObserver != nil else { return }
        player.stop()
        engine.stop()
        if attached {
            engine.detach(player)
            attached = false
        }
        started = false
        activeFormat = nil
    }

    private func rebuildAfterConfigurationChange() {
        guard started, let activeFormat else { return }
        player.stop()
        engine.stop()
        if attached {
            engine.detach(player)
            attached = false
        }
        started = false
        do {
            try start(format: activeFormat)
        } catch {
            self.activeFormat = nil
            onFailure?("The Sing output route changed and could not be restarted: \(error.localizedDescription)")
        }
    }

    private func makeFormat(_ format: SingAudioFormat) throws -> AVAudioFormat {
        guard
            let value = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: format.sampleRate,
                channels: AVAudioChannelCount(format.channelCount),
                interleaved: false
            )
        else {
            throw SingAudioError.unavailable("The Music output format could not be created.")
        }
        return value
    }
}
