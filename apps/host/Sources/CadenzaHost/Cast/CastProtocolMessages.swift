import Foundation

/// The JSON payloads Cadenza sends to a Cast device, and the replies it reads back.
enum CastProtocolMessages {
    static let connectionNamespace = "urn:x-cast:com.google.cast.tp.connection"
    static let heartbeatNamespace = "urn:x-cast:com.google.cast.tp.heartbeat"
    static let receiverNamespace = "urn:x-cast:com.google.cast.receiver"
    static let mediaNamespace = "urn:x-cast:com.google.cast.media"
    static let senderId = "sender-0"
    static let receiverId = "receiver-0"
    /// Google's Default Media Receiver plays an audio stream without a registered receiver app.
    static let defaultMediaReceiverAppId = "CC1AD845"

    static func connect(to destination: String) -> CastMessage {
        message(connectionNamespace, to: destination, ["type": "CONNECT"])
    }

    static func pong(to destination: String) -> CastMessage {
        message(heartbeatNamespace, to: destination, ["type": "PONG"])
    }

    static func receiverStatus(requestId: Int) -> CastMessage {
        message(receiverNamespace, to: receiverId, ["type": "GET_STATUS", "requestId": requestId])
    }

    static func launch(appId: String, requestId: Int) -> CastMessage {
        message(receiverNamespace, to: receiverId, ["type": "LAUNCH", "appId": appId, "requestId": requestId])
    }

    static func loadAudio(
        url: String, transportId: String, sessionId: String, title: String, requestId: Int,
        contentType: String = "audio/aac", streamType: String = "LIVE",
        subtitleURL: String? = nil
    ) -> CastMessage {
        var media: [String: Any] = [
            "contentId": url,
            "contentType": contentType,
            "streamType": streamType,
            "metadata": ["metadataType": 0, "title": title],
        ]
        var body: [String: Any] = [
            "type": "LOAD",
            "requestId": requestId,
            "sessionId": sessionId,
            "autoplay": true,
        ]
        // The Default Media Receiver draws a WebVTT track on screen when it is active, which gives karaoke subtitles.
        if let subtitleURL {
            media["tracks"] = [
                [
                    "trackId": 1, "type": "TEXT", "subtype": "SUBTITLES", "trackContentId": subtitleURL,
                    "trackContentType": "text/vtt", "name": "Cadenza Lyrics", "language": "en",
                ]
            ]
            body["activeTrackIds"] = [1]
        }
        body["media"] = media
        return message(mediaNamespace, to: transportId, body)
    }

    static func stop(sessionId: String, requestId: Int) -> CastMessage {
        message(receiverNamespace, to: receiverId, ["type": "STOP", "sessionId": sessionId, "requestId": requestId])
    }

    static func isPing(_ message: CastMessage) -> Bool {
        messageType(message) == "PING"
    }

    static func isReceiverStatus(_ message: CastMessage) -> Bool {
        messageType(message) == "RECEIVER_STATUS"
    }

    /// The transport and session IDs of the running app, once the device reports it.
    static func runningSession(in message: CastMessage, appId: String) -> (transportId: String, sessionId: String)? {
        guard messageType(message) == "RECEIVER_STATUS",
            let object = jsonObject(message.payload),
            let status = object["status"] as? [String: Any],
            let applications = status["applications"] as? [[String: Any]]
        else { return nil }

        for application in applications where application["appId"] as? String == appId {
            guard let transportId = application["transportId"] as? String,
                let sessionId = application["sessionId"] as? String
            else { continue }

            return (transportId, sessionId)
        }

        return nil
    }

    private static func message(_ namespace: String, to destination: String, _ body: [String: Any]) -> CastMessage {
        CastMessage(
            sourceId: senderId, destinationId: destination, namespace: namespace, payload: json(body))
    }

    private static func messageType(_ message: CastMessage) -> String? {
        jsonObject(message.payload)?["type"] as? String
    }

    private static func json(_ body: [String: Any]) -> String {
        let options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: options) else { return "{}" }

        return String(decoding: data, as: UTF8.self)
    }

    private static func jsonObject(_ text: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
    }
}
