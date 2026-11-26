import Foundation
import Testing

@testable import CadenzaHost

@MainActor
struct CastStageHubTests {
    final class Recorder {
        var messages: [(Data, Bool)] = []
        var closed = false
    }

    private func session(_ hub: StageHub, id: String, role: String, recorder: Recorder) -> StageHub.Session {
        let session = StageHub.Session(
            id: id, role: role,
            send: { payload, binary in
                recorder.messages.append((payload, binary))
                return true
            },
            close: { recorder.closed = true })
        hub.attach(session)
        return session
    }

    private func profile(token: String? = nil, transport: String = "cadenza_web_tv_stage") -> Data {
        var object: [String: Any] = [
            "version": 1, "type": "RECEIVER_PROFILE", "receiverId": "tv-1", "transportType": transport,
            "displayName": "Living room", "hasDisplay": true, "isStandby": false, "isTouchSupported": false,
            "maxAudioChannels": 6, "supportedCodecs": ["aac", "pcm"],
        ]
        if let token { object["receiverToken"] = token }
        return try! JSONSerialization.data(withJSONObject: object)
    }

    private func type(of data: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["type"] as? String
    }

    @Test func anUnpairedReceiverGetsAPINAndNoTrackData() throws {
        let hub = StageHub(receivers: StageReceivers(file: nil))
        let recorder = Recorder()
        _ = session(hub, id: "s1", role: "tv_stage", recorder: recorder)
        hub.publishSuite(Data("{\"type\":\"TRACK_SUITE_PAYLOAD\"}".utf8))
        hub.receive(profile(), from: "s1")
        let sent = try #require(recorder.messages.first)
        #expect(type(of: sent.0) == "STAGE_PAIRING")
        #expect(recorder.messages.count == 1)
        #expect(hub.approvedSessions.isEmpty)
    }

    @Test func approvingThePINAcceptsTheReceiverWithATokenAndSendsTheCurrentSuite() throws {
        let hub = StageHub(receivers: StageReceivers(file: nil))
        let recorder = Recorder()
        _ = session(hub, id: "s1", role: "tv_stage", recorder: recorder)
        hub.publishSuite(Data("{\"type\":\"TRACK_SUITE_PAYLOAD\"}".utf8))
        hub.receive(profile(), from: "s1")
        let pairing = try #require(
            JSONSerialization.jsonObject(with: recorder.messages[0].0) as? [String: Any])
        let pin = try #require(pairing["pin"] as? String)

        #expect(hub.approve(pin: pin))
        #expect(hub.approvedSessions.map(\.id) == ["s1"])
        #expect(recorder.messages.contains { type(of: $0.0) == "STAGE_ACCEPTED" })
        #expect(recorder.messages.last.map { type(of: $0.0) } == "TRACK_SUITE_PAYLOAD")
    }

    @Test func aWrongPINApprovesNothing() throws {
        let hub = StageHub(receivers: StageReceivers(file: nil))
        let recorder = Recorder()
        _ = session(hub, id: "s1", role: "tv_stage", recorder: recorder)
        hub.receive(profile(), from: "s1")
        let pin = try #require(hub.receivers.pending.first?.pin)
        let other = String(format: "%04d", (Int(pin)! + 1) % 10_000)
        #expect(!hub.approve(pin: other))
        #expect(hub.approvedSessions.isEmpty)
    }

    @Test func aReceiverWithAValidTokenIsApprovedWithoutAPIN() throws {
        let receivers = StageReceivers(file: nil)
        let now = Date()
        _ = receivers.issuePIN(sessionId: "old", receiverId: "tv-1", name: "Living room", now: now)
        let token = try #require(receivers.approve(sessionId: "old", now: now))
        let hub = StageHub(receivers: receivers)
        let recorder = Recorder()
        _ = session(hub, id: "s2", role: "tv_stage", recorder: recorder)
        hub.receive(profile(token: token), from: "s2")
        #expect(hub.approvedSessions.map(\.id) == ["s2"])
        #expect(recorder.messages.isEmpty)
    }

    @Test func aProfileForTheWrongRoleOrAnInvalidOneClosesTheSocket() {
        let hub = StageHub(receivers: StageReceivers(file: nil))
        let wrongRole = Recorder()
        _ = session(hub, id: "s1", role: "android_tv_receiver", recorder: wrongRole)
        hub.receive(profile(), from: "s1")
        #expect(wrongRole.closed)

        let invalid = Recorder()
        _ = session(hub, id: "s2", role: "tv_stage", recorder: invalid)
        hub.receive(Data("{}".utf8), from: "s2")
        #expect(invalid.closed)
    }

    @Test func detachingASocketDropsItsPendingPIN() {
        let hub = StageHub(receivers: StageReceivers(file: nil))
        let recorder = Recorder()
        _ = session(hub, id: "s1", role: "tv_stage", recorder: recorder)
        hub.receive(profile(), from: "s1")
        #expect(!hub.receivers.pending.isEmpty)
        hub.detach("s1")
        #expect(hub.receivers.pending.isEmpty)
    }
}
