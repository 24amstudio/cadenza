import AVFAudio
import Foundation

/// Sends Music's output to one Cast device. Stereo is encoded to AAC and 5.1 to AC-3,
/// and the Default Media Receiver plays the Host's LAN stream over chunked HTTP.
/// When casting music videos with the custom receiver, forwards Widevine HLS metadata,
/// streams local DRM-free `.mp4`/`.m4v` files with byte ranges, or enters Karaoke Theater Mode.
@MainActor
final class CastTransmitter {
    enum State: Equatable, Sendable {
        case idle
        case starting(device: String)
        case transmitting(device: String)
        case failed(device: String, reason: String)
    }

    struct VideoSessionMetadata: Equatable, Sendable {
        var title: String
        var artist: String
        var route: CastVideoRoute
        var lipSyncOffsetMs: Int
    }

    private(set) var state: State = .idle
    var onChange: ((State) -> Void)?

    private let capture: SingCaptureRoute = CoreAudioSingRoute()
    let envelopeCollector = VideoAudioEnvelopeCollector()
    private var server = CastAudioStreamServer(codec: .aac)
    private var codec: CastAudioCodec = .aac
    private var encoder: CastAACEncoder?
    private var ac3Encoder: CastAC3Encoder?
    private var flacEncoder: CastFLACEncoder?
    private var control: CastControlConnection?
    private var deviceName = ""
    private var transportId: String?
    private var sessionId: String?
    private var launched = false
    private var requestId = 0
    private var videoSession: VideoSessionMetadata?

    var streamPort: UInt16 { server.port }

    func start(
        device: CastDiscovery.Device,
        lanHost: String,
        videoSession: VideoSessionMetadata? = nil,
        localVideoFile: URL? = nil,
        artwork: Data? = nil,
        motion: Data? = nil,
        presentationMode: CastPresentationMode = .auto
    ) async {
        stop()
        deviceName = device.name
        self.videoSession = videoSession
        envelopeCollector.reset()
        set(.starting(device: device.name))
        do {
            guard let format = capture.format, format.channelCount == 2 || format.channelCount == 6 else {
                throw SingAudioError.unavailable("Cast transmission needs Music's stereo or 5.1 output.")
            }
            // Select codec based on channel count and presentation mode
            let codec: CastAudioCodec
            if format.channelCount == 6 {
                codec = .ac3
            } else if presentationMode == .fullSuite && format.channelCount >= 2 {
                // Full suite with multi-channel: use AC-3 bitstream mode
                codec = .ac3
            } else {
                codec = .aac
            }
            self.codec = codec
            let server = CastAudioStreamServer(codec: codec)
            self.server = server
            // Initialize the appropriate encoder
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
            } else if presentationMode == .fullSuite {
                // Use FLAC for lossless full-suite transmission
                flacEncoder = CastFLACEncoder()
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
            server.setMediaAssets(videoFile: localVideoFile, artwork: artwork, motion: motion)
            let aac = encoder
            let ac3 = ac3Encoder
            let flac = flacEncoder
            let collector = envelopeCollector
            try await capture.start { buffer in
                collector.append(buffer: buffer)
                let pcmData: Data
                let samples = buffer.samples
                let channelData = samples.channelData
                if let chData = channelData {
                    let channels = Int(buffer.format.channelCount)
                    let frameCount = Int(samples.frameLength)
                    var interleaved = [Float](repeating: 0, count: frameCount * channels)
                    for channel in 0..<channels {
                        let channelFloat = chData[channel]
                        for frame in 0..<frameCount {
                            interleaved[frame * channels + frame] = channelFloat[frame]
                        }
                    }
                    pcmData = interleaved.withUnsafeBytes { Data($0) }
                } else {
                    pcmData = Data()
                }
                if let ac3 {
                    ac3.encode(buffer.samples)
                } else if let flac {
                    for frame in flac.encode(pcmData) { server.publish(frame) }
                } else if let aac {
                    for frame in aac.encode(buffer.samples) { server.publish(frame) }
                }
            }
            let url = "http://\(lanHost):\(port)\(codec.path)?seq=\(UUID().uuidString.prefix(8))"
            streamURL = url
            self.lanHost = lanHost
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

    func updateMediaAssets(localVideoFile: URL? = nil, artwork: Data? = nil, motion: Data? = nil) {
        server.setMediaAssets(videoFile: localVideoFile, artwork: artwork, motion: motion)
    }

    func updateVideoSession(_ session: VideoSessionMetadata) {
        self.videoSession = session
        guard let transportId else { return }
        sendSessionPayload(session, transportId: transportId)
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
        lanHost = nil
        lastKaraoke = nil
        videoSession = nil
        envelopeCollector.reset()
        set(.idle)
    }

    private var streamURL: String?
    private var lanHost: String?
    private var lastKaraoke: String?

    // The Default Media Receiver plays audio alone. A custom receiver app, set in defaults, shows the karaoke lines.
    private var receiverAppId: String {
        UserDefaults.standard.string(forKey: "castReceiverAppId") ?? CastProtocolMessages.defaultMediaReceiverAppId
    }

    /// Sends the karaoke line and optional English translation to the receiver app once it runs.
    func sendKaraoke(line: String, next: String, translation: String = "") {
        guard state != .idle, let transportId else { return }
        let key = line + "\u{1F}" + next + "\u{1F}" + translation
        guard key != lastKaraoke else { return }
        lastKaraoke = key
        var payload: [String: Any] = ["type": "line", "text": line, "next": next]
        if !translation.isEmpty { payload["translation"] = translation }
        control?.send(CastProtocolMessages.karaoke(payload, transportId: transportId))
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
        if let videoSession {
            switch videoSession.route {
            case .widevineHLS(let hlsURL, let licenseURL, let certURL, let mediaUserToken, let developerToken):
                var customData: [String: Any] = [
                    "mediaUserToken": mediaUserToken,
                    "developerToken": developerToken,
                ]
                if let licenseURL { customData["licenseUrl"] = licenseURL.absoluteString }
                if let certURL { customData["certUrl"] = certURL.absoluteString }
                // Forward Widevine license requests through Host to license server
                control?.send(
                    CastProtocolMessages.loadAudio(
                        url: hlsURL.absoluteString,
                        transportId: transportId,
                        sessionId: sessionId,
                        title: videoSession.title,
                        requestId: requestId,
                        contentType: "application/x-mpegurl",
                        streamType: "BUFFERED",
                        customData: customData))
                // Send license request forward if license URL is configured
                if let licenseURL {
                    let licenseForwardPayload: [String: Any] = [
                        "type": "license_request",
                        "licenseUrl": licenseURL.absoluteString,
                        "certUrl": certURL?.absoluteString ?? "",
                        "everyone": true,
                        "rmd": "Cadenza",
                    ]
                    control?.send(CastProtocolMessages.karaoke(licenseForwardPayload, transportId: transportId))
                }
                sendSessionPayload(videoSession, transportId: transportId)
                set(.transmitting(device: deviceName))
                return
            case .localVideo:
                if let lanHost, server.port != 0 {
                    // fMP4 low-latency path: stream via the host's HTTP stream server
                    let videoURL = "http://\(lanHost):\(server.port)/cast/video.mp4"
                    control?.send(
                        CastProtocolMessages.loadAudio(
                            url: videoURL,
                            transportId: transportId,
                            sessionId: sessionId,
                            title: videoSession.title,
                            requestId: requestId,
                            contentType: "video/mp4",
                            streamType: "BUFFERED"))
                    sendSessionPayload(videoSession, transportId: transportId)
                    set(.transmitting(device: deviceName))
                    return
                }
            case .theater:
                break
            }
        }
        // Use the appropriate content type based on codec for low-latency audio
        let contentType: String
        switch codec {
        case .ac3: contentType = "audio/ac3"
        case .aac: contentType = "audio/aac"
        case .flac: contentType = "audio/flac"
        }
        control?.send(
            CastProtocolMessages.loadAudio(
                url: streamURL, transportId: transportId, sessionId: sessionId,
                title: videoSession?.title ?? "Cadenza",
                requestId: requestId, contentType: contentType))
        if let videoSession {
            sendSessionPayload(videoSession, transportId: transportId)
        } else {
            let mode =
                UserDefaults.standard.string(forKey: "castPresentationMode") == "fullSuite"
                ? "full_suite" : "audio_only"
            control?.send(
                CastProtocolMessages.karaoke(
                    ["type": "session", "title": "Cadenza", "mode": mode], transportId: transportId))
        }
        set(.transmitting(device: deviceName))
    }

    private func sendSessionPayload(_ session: VideoSessionMetadata, transportId: String) {
        let mode: String
        var payload: [String: Any] = [
            "type": "session",
            "title": session.title,
            "artist": session.artist,
            "lipSyncOffsetMs": session.lipSyncOffsetMs,
        ]
        switch session.route {
        case .widevineHLS, .localVideo:
            mode = "karaoke_video"
        case .theater(let artworkURL, let motionURL):
            mode =
                UserDefaults.standard.string(forKey: "castPresentationMode") == "audioOnly"
                ? "audio_only" : "theater"
            if let artworkURL { payload["artworkUrl"] = artworkURL.absoluteString }
            if let motionURL { payload["motionUrl"] = motionURL.absoluteString }
        }
        payload["mode"] = mode
        control?.send(CastProtocolMessages.karaoke(payload, transportId: transportId))
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
