import AVFAudio
import Foundation

/// Plays processed buffers through the user's current macOS output device.
final class AVAudioSingOutput: SingOutputSink, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var attached = false
    private var started = false
    private var activeFormat: SingAudioFormat?
    private var rebuildScheduled = false
    private var configurationObserver: NSObjectProtocol?
    var onFailure: (@Sendable (String) -> Void)?

    init() {
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

    func stop() {
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
