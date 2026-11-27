import AVFAudio
import AVFoundation
import Foundation

/// The Mac's microphone, read only during a room calibration. It starts only when access was already granted in
/// Settings, after the explanation there. This type never asks for access itself.
final class RoomMicrophone: @unchecked Sendable {
    enum Failure: Error, Equatable {
        case notAuthorized
        case unavailable
    }

    /// The calibration correlates at 48 kHz, so a microphone at another rate is not used.
    static let requiredSampleRate = 48_000.0

    static var isAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private let engine = AVAudioEngine()
    private var running = false

    /// Starts the input. `onBlock` receives mono Float32 samples from the audio thread.
    func start(onBlock: @escaping @Sendable ([Float]) -> Void) throws {
        guard Self.isAuthorized else { throw Failure.notAuthorized }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate == Self.requiredSampleRate, format.channelCount > 0 else {
            throw Failure.unavailable
        }
        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            onBlock(Array(UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength))))
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw Failure.unavailable
        }
        running = true
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
    }
}
