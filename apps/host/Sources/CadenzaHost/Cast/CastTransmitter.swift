import AVFAudio
import Foundation

/// Sends Music's output to one Cast device. Stereo is encoded to AAC and 5.1 to AC-3,
/// and the Default Media Receiver plays the Host's LAN stream over chunked HTTP. The route, not this type, decides
/// whether a local DRM-free `.mp4`/`.m4v` music video is sent. Catalog video never reaches a Cast device.
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
        /// The opaque suite ID that names the video and its subtitles on the LAN stream server.
        var suiteId: String
        /// The karaoke WebVTT for the current track, with the saved nudge and lip-sync offset applied.
        var subtitles: String
        var lipSyncOffsetMs: Int
    }

    /// A third-party Cast app that opens a URL in the TV's own browser, so the TV needs no installed Cadenza receiver.
    /// Experimental: the app ID is whatever the person found for a URL-loading receiver such as DashCast.
    struct WebLoader: Equatable, Sendable {
        var appId: String
        var url: String
        /// The page is reloaded this often, so a TV that slept or lost its socket comes back on its own.
        static let refreshInterval: Duration = .seconds(480)
    }

    private(set) var state: State = .idle
    var onChange: ((State) -> Void)?

    private let capture: SingCaptureRoute = CoreAudioSingRoute()
    let envelopeCollector = VideoAudioEnvelopeCollector()
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
    private var videoSession: VideoSessionMetadata?
    private var webLoader: WebLoader?
    private var webLoaderSession: (transportId: String, sessionId: String)?
    private var webLoaderRefresh: Task<Void, Never>?

    var streamPort: UInt16 { server.port }

    func start(
        device: CastDiscovery.Device,
        lanHost: String,
        videoSession: VideoSessionMetadata? = nil,
        localVideoFile: URL? = nil,
        artwork: Data? = nil,
        motion: Data? = nil,
        webLoader: WebLoader? = nil
    ) async {
        stop()
        deviceName = device.name
        self.videoSession = videoSession
        envelopeCollector.reset()
        set(.starting(device: device.name))
        if let webLoader {
            // The TV's browser pulls audio and track data from the stage channel, so no capture or encoder runs here.
            self.webLoader = webLoader
            connect(device)
            return
        }
        do {
            guard let format = capture.format, let codec = CastAudioCodec.forChannelCount(format.channelCount) else {
                throw SingAudioError.unavailable("Cast transmission needs Music's stereo or 5.1 output.")
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
            let collector = envelopeCollector
            try await capture.start { buffer in
                collector.append(buffer: buffer)
                if let ac3 {
                    ac3.encode(buffer.samples)
                } else if let aac {
                    for frame in aac.encode(buffer.samples) { server.publish(frame) }
                }
            }
            let url = "http://\(lanHost):\(port)\(codec.path)?seq=\(UUID().uuidString.prefix(8))"
            streamURL = url
            self.lanHost = lanHost
            connect(device)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func connect(_ device: CastDiscovery.Device) {
        control = CastControlConnection(
            endpoint: device.endpoint,
            onMessage: { [weak self] message in Task { @MainActor in self?.receive(message) } },
            onClose: { [weak self] reason in Task { @MainActor in self?.closed(reason) } })
        control?.start()
        control?.send(CastProtocolMessages.connect(to: CastProtocolMessages.receiverId))
        requestId += 1
        control?.send(CastProtocolMessages.receiverStatus(requestId: requestId))
    }

    func updateMediaAssets(localVideoFile: URL? = nil, artwork: Data? = nil, motion: Data? = nil) {
        server.setMediaAssets(videoFile: localVideoFile, artwork: artwork, motion: motion)
    }

    /// Replaces the subtitles of the video that is playing. The receiver reads the new cues on its next fetch.
    func updateVideoSession(_ session: VideoSessionMetadata) {
        videoSession = session
        server.setSubtitles(session.subtitles)
    }

    /// Replaces the karaoke cues after a nudge or a lip-sync change. The receiver reads them on its next fetch.
    func updateSubtitles(_ vtt: String) {
        server.setSubtitles(vtt)
    }

    func stop() {
        webLoaderRefresh?.cancel()
        webLoaderRefresh = nil
        if let webLoaderSession {
            requestId += 1
            control?.send(CastProtocolMessages.stop(sessionId: webLoaderSession.sessionId, requestId: requestId))
        }
        webLoader = nil
        webLoaderSession = nil
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
        videoSession = nil
        envelopeCollector.reset()
        set(.idle)
    }

    private var streamURL: String?
    private var lanHost: String?

    private func receive(_ message: CastMessage) {
        if CastProtocolMessages.isPing(message) {
            control?.send(CastProtocolMessages.pong(to: message.sourceId))

            return
        }
        if let webLoader {
            receiveWebLoader(message, loader: webLoader)

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
                CastProtocolMessages.launch(appId: CastProtocolMessages.defaultMediaReceiverAppId, requestId: requestId)
            )
        }
    }

    /// Launches the URL-loading app, then opens the stage page once the device reports its session.
    private func receiveWebLoader(_ message: CastMessage, loader: WebLoader) {
        if webLoaderSession == nil,
            let session = CastProtocolMessages.runningSession(in: message, appId: loader.appId)
        {
            webLoaderSession = session
            control?.send(CastProtocolMessages.connect(to: session.transportId))
            loadWebPage(loader)
            set(.transmitting(device: deviceName))
            startWebLoaderRefresh()

            return
        }
        if CastProtocolMessages.isReceiverStatus(message), !launched {
            launched = true
            requestId += 1
            control?.send(CastProtocolMessages.launch(appId: loader.appId, requestId: requestId))
        }
    }

    private func loadWebPage(_ loader: WebLoader) {
        guard let webLoaderSession else { return }
        requestId += 1
        control?.send(
            CastProtocolMessages.loadWebPage(
                url: loader.url, transportId: webLoaderSession.transportId,
                sessionId: webLoaderSession.sessionId, requestId: requestId))
    }

    /// Reloads the page on an interval. A TV that slept or dropped its socket reopens the stage without a person
    /// touching it, and a page that is already current simply reloads.
    private func startWebLoaderRefresh() {
        webLoaderRefresh?.cancel()
        webLoaderRefresh = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: WebLoader.refreshInterval)
                guard !Task.isCancelled, let self, let loader = self.webLoader else { return }
                self.loadWebPage(loader)
            }
        }
    }

    private func loadStream(transportId: String, sessionId: String) {
        guard let streamURL else { return }
        requestId += 1
        // The stream server holds the DRM-free file and serves it with byte ranges, so the receiver loads it as an MP4.
        if let videoSession, let lanHost, server.port != 0 {
            let base = "http://\(lanHost):\(server.port)/api/v1/cast/video/\(videoSession.suiteId)"
            control?.send(
                CastProtocolMessages.loadAudio(
                    url: "\(base)/video.mp4",
                    transportId: transportId,
                    sessionId: sessionId,
                    title: videoSession.title,
                    requestId: requestId,
                    contentType: "video/mp4",
                    streamType: "BUFFERED",
                    subtitleURL: "\(base)/lyrics.vtt"))
            set(.transmitting(device: deviceName))
            return
        }
        let contentType = codec.contentType
        control?.send(
            CastProtocolMessages.loadAudio(
                url: streamURL, transportId: transportId, sessionId: sessionId,
                title: videoSession?.title ?? "Cadenza",
                requestId: requestId, contentType: contentType))
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
