import AVFAudio
import Foundation

/// Sends Music's stereo output to one Cast device. The device plays the Default Media Receiver with the Host's LAN
/// stream. Audio is captured from Music, encoded to AAC, and served over chunked HTTP.
/// The Cast protocol path has not been run against a device yet.
@MainActor
final class CastTransmitter {
    enum State: Equatable, Sendable {
        case idle
        case starting(device: String)
        case transmitting(device: String)
        case failed(device: String, reason: String)
    }

    private(set) var state: State = .idle
    var onChange: ((State) -> Void)?

    private let capture: SingCaptureRoute = CoreAudioSingRoute()
    private let server = CastAudioStreamServer()
    private var encoder: CastAACEncoder?
    private var control: CastControlConnection?
    private var deviceName = ""
    private var transportId: String?
    private var sessionId: String?
    private var launched = false
    private var requestId = 0

    func start(device: CastDiscovery.Device, lanHost: String) async {
        stop()
        deviceName = device.name
        set(.starting(device: device.name))
        do {
            guard let format = capture.format, format.channelCount == 2 else {
                throw SingAudioError.unavailable("Cast transmission needs Music's stereo output.")
            }
            guard
                let inputFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32, sampleRate: format.sampleRate,
                    channels: AVAudioChannelCount(format.channelCount), interleaved: false),
                let encoder = CastAACEncoder(sampleRate: format.sampleRate, channels: 2, inputFormat: inputFormat)
            else {
                throw SingAudioError.unavailable("The Music output could not be encoded for Cast.")
            }
            self.encoder = encoder
            let port = try await server.start()
            let server = self.server
            try await capture.start { buffer in
                for frame in encoder.encode(buffer.samples) { server.publish(frame) }
            }
            let url = "http://\(lanHost):\(port)\(CastAudioStreamServer.path)?seq=\(UUID().uuidString.prefix(8))"
            streamURL = url
            control = CastControlConnection(
                endpoint: device.endpoint,
                onMessage: { [weak self] message in Task { @MainActor in self?.receive(message) } },
                onClose: { [weak self] reason in Task { @MainActor in self?.closed(reason) } })
            control?.start()
            control?.send(CastProtocolMessages.connect(to: CastProtocolMessages.receiverId))
            requestId += 1
            control?.send(CastProtocolMessages.receiverStatus(requestId: requestId))
        } catch {
            fail(error.localizedDescription)
        }
    }

    func stop() {
        if let sessionId {
            requestId += 1
            control?.send(CastProtocolMessages.stop(sessionId: sessionId, requestId: requestId))
        }
        control?.cancel()
        control = nil
        capture.stop()
        server.stop()
        encoder = nil
        transportId = nil
        sessionId = nil
        launched = false
        streamURL = nil
        set(.idle)
    }

    private var streamURL: String?

    private func receive(_ message: CastMessage) {
        if CastProtocolMessages.isPing(message) {
            control?.send(CastProtocolMessages.pong(to: message.sourceId))

            return
        }
        guard transportId == nil else { return }
        if let session = CastProtocolMessages.runningSession(
            in: message, appId: CastProtocolMessages.defaultMediaReceiverAppId)
        {
            transportId = session.transportId
            sessionId = session.sessionId
            control?.send(CastProtocolMessages.connect(to: session.transportId))
            loadStream(transportId: session.transportId, sessionId: session.sessionId)
        } else if CastProtocolMessages.isReceiverStatus(message), !launched {
            launched = true
            requestId += 1
            control?.send(
                CastProtocolMessages.launch(appId: CastProtocolMessages.defaultMediaReceiverAppId, requestId: requestId))
        }
    }

    private func loadStream(transportId: String, sessionId: String) {
        guard let streamURL else { return }
        requestId += 1
        control?.send(
            CastProtocolMessages.loadAudio(
                url: streamURL, transportId: transportId, sessionId: sessionId, title: "Cadenza",
                requestId: requestId))
        set(.transmitting(device: deviceName))
    }

    private func closed(_ reason: String) {
        guard state != .idle else { return }
        fail(reason)
    }

    private func fail(_ reason: String) {
        let device = deviceName
        stop()
        set(.failed(device: device, reason: reason))
    }

    private func set(_ next: State) {
        state = next
        onChange?(next)
    }
}
