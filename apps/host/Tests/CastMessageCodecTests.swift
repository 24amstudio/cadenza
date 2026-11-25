import Testing

@testable import CadenzaHost

struct CastMessageCodecTests {
    @Test func aMessageSurvivesEncodingAndDecoding() {
        let message = CastMessage(
            sourceId: "sender-0", destinationId: "receiver-0", namespace: "urn:x-cast:com.google.cast.receiver",
            payload: #"{"type":"GET_STATUS","requestId":1}"#)

        #expect(CastMessageCodec.decode(CastMessageCodec.encode(message)) == message)
    }

    @Test func theFramePrefixAnnouncesTheBodyLength() {
        let message = CastProtocolMessages.connect(to: CastProtocolMessages.receiverId)
        let framed = CastMessageCodec.frame(message)
        let body = Array(framed.dropFirst(4))

        #expect(CastMessageCodec.bodyLength(prefix: Array(framed.prefix(4))) == body.count)
        #expect(CastMessageCodec.decode(body) == message)
    }

    @Test func aRunningAudioSessionIsFoundByItsAppIdentifier() {
        let status = CastMessage(
            sourceId: "receiver-0", destinationId: "sender-0", namespace: CastProtocolMessages.receiverNamespace,
            payload: """
                {"type":"RECEIVER_STATUS","requestId":1,"status":{"applications":[
                {"appId":"OTHER","sessionId":"s-other","transportId":"t-other"},
                {"appId":"CC1AD845","sessionId":"s-1","transportId":"t-1"}]}}
                """)

        let session = CastProtocolMessages.runningSession(
            in: status, appId: CastProtocolMessages.defaultMediaReceiverAppId)

        #expect(session?.transportId == "t-1")
        #expect(session?.sessionId == "s-1")
        #expect(CastProtocolMessages.isReceiverStatus(status))
    }

    @Test func theLoadRequestNamesTheStreamAndItsAudioType() {
        let load = CastProtocolMessages.loadAudio(
            url: "http://192.168.1.5:8080/cast/audio.aac?seq=1", transportId: "t-1", sessionId: "s-1",
            title: "Cadenza", requestId: 3)

        #expect(load.destinationId == "t-1")
        #expect(load.payload.contains(#""contentType":"audio/aac""#))
        #expect(load.payload.contains("192.168.1.5:8080"))
    }
}

struct CastAudioCodecTests {
    @Test func aSixChannelStreamIsServedAsAC3AndAStereoStreamAsAAC() throws {
        #expect(CastAudioCodec.ac3.path == "/cast/audio.ac3")
        #expect(CastAudioCodec.ac3.contentType == "audio/ac3")
        #expect(CastAudioCodec.aac.contentType == "audio/aac")

        let load = CastProtocolMessages.loadAudio(
            url: "http://192.168.1.2:8080/cast/audio.ac3?seq=1", transportId: "t", sessionId: "s", title: "Cadenza",
            requestId: 2, contentType: CastAudioCodec.ac3.contentType)
        #expect(load.payload.contains("\"contentType\":\"audio/ac3\""))
    }
}

struct CastKaraokeMessageTests {
    @Test func aKaraokeLineGoesToTheReceiverOnTheCadenzaNamespace() {
        let message = CastProtocolMessages.karaoke(
            ["type": "line", "text": "Pedida", "next": "perfeita"], transportId: "transport-1")

        #expect(message.namespace == CastProtocolMessages.karaokeNamespace)
        #expect(message.destinationId == "transport-1")
        #expect(message.payload.contains("\"text\":\"Pedida\""))
    }
}
