import AVFAudio
import Foundation

/// Sends Music's output to one Cast device. Stereo is encoded to AAC and 5.1 to AC-3, and the Default Media Receiver
/// plays the Host's LAN stream over chunked HTTP.
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
    private var server = CastAudioStreamServer(codec: .aac)
    private var codec: CastAudioCodec = .aac
    private var encoder: CastAACEncoder?
    private var ac3Encoder: CastAC3Encoder?
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
            guard let format = capture.format, format.channelCount == 2 || format.channelCount == 6 else {
                throw SingAudioError.unavailable("Cast transmission needs Music's stereo or 5.1 output.")
            }
            let codec: CastAudioCodec = format.channelCount == 6 ? .ac3 : .aac
            self.codec = codec
            let server = CastAudioStreamServer(codec: codec)
            self.server = server
            if codec == .ac3 {
                guard
                    let helper = CastAC3Encoder.helperURL(),
                    let ac3 = CastAC3Encoder(
                        helper: helper, sampleRate: format.sampleRate,
                        onOutput: { data in server.publish([UInt8](data)) })
                else {
                    throw SingAudioError.unavailable(
                        "Cast 5.1 needs the AC-3 encoder, which this Host build does not include.")
                }
                ac3Encoder = ac3
            } else {
                guard
                    let inputFormat = AVAudioFormat(
                        commonFormat: .pcmFormatFloat32, sampleRate: format.sampleRate,
                        channels: AVAudioChannelCount(format.channelCount), interleaved: false),
                    let aac = CastAACEncoder(sampleRate: format.sampleRate, channels: 2, inputFormat: inputFormat)
                else {
                    throw SingAudioError.unavailable("The Music output could not be encoded for Cast.")
                }
                encoder = aac
            }
            let port = try await server.start()
            let aac = encoder
            let ac3 = ac3Encoder
            try await capture.start { buffer in
                if let ac3 {
                    ac3.encode(buffer.samples)
                } else if let aac {
                    for frame in aac.encode(buffer.samples) { server.publish(frame) }
                }
            }
            let url = "http://\(lanHost):\(port)\(codec.path)?seq=\(UUID().uuidString.prefix(8))"
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
        ac3Encoder?.stop()
        ac3Encoder = nil
        transportId = nil
        sessionId = nil
        launched = false
        streamURL = nil
        lastKaraoke = nil
        set(.idle)
    }

    private var streamURL: String?
    private var lastKaraoke: String?

    // The Default Media Receiver plays audio alone. A custom receiver app, set in defaults, shows the karaoke lines.
    private var receiverAppId: String {
        UserDefaults.standard.string(forKey: "castReceiverAppId") ?? CastProtocolMessages.defaultMediaReceiverAppId
    }

    /// Sends the karaoke line to the receiver app once it runs. Repeats of the same line are not sent again.
    func sendKaraoke(line: String, next: String) {
        guard state != .idle, let transportId else { return }
        let key = line + "\u{1F}" + next
        guard key != lastKaraoke else { return }
        lastKaraoke = key
        control?.send(
            CastProtocolMessages.karaoke(["type": "line", "text": line, "next": next], transportId: transportId))
    }

    private func receive(_ message: CastMessage) {
        if CastProtocolMessages.isPing(message) {
            control?.send(CastProtocolMessages.pong(to: message.sourceId))

            return
        }
        guard transportId == nil else { return }
        if let session = CastProtocolMessages.runningSession(
            in: message, appId: receiverAppId)
        {
            transportId = session.transportId
            sessionId = session.sessionId
            control?.send(CastProtocolMessages.connect(to: session.transportId))
            loadStream(transportId: session.transportId, sessionId: session.sessionId)
        } else if CastProtocolMessages.isReceiverStatus(message), !launched {
            launched = true
            requestId += 1
            control?.send(
                CastProtocolMessages.launch(appId: receiverAppId, requestId: requestId)
            )
        }
    }

    private func loadStream(transportId: String, sessionId: String) {
        guard let streamURL else { return }
        requestId += 1
        control?.send(
            CastProtocolMessages.loadAudio(
                url: streamURL, transportId: transportId, sessionId: sessionId, title: "Cadenza",
                requestId: requestId, contentType: codec.contentType))
        let mode =
            UserDefaults.standard.string(forKey: "castPresentationMode") == "fullSuite" ? "full_suite" : "audio_only"
        control?.send(
            CastProtocolMessages.karaoke(
                ["type": "session", "title": "Cadenza", "mode": mode], transportId: transportId))
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
