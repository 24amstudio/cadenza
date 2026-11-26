import Foundation
import Testing

@testable import CadenzaHost

@MainActor
struct CastStageReceiversTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "stage-receivers-\(UUID().uuidString).json")
    }

    @Test func aPINIsFourDigitsAndStaysWithItsSocketUntilItExpires() {
        let receivers = StageReceivers(file: nil)
        let start = Date(timeIntervalSince1970: 1_000)
        let first = receivers.issuePIN(sessionId: "s1", receiverId: "tv", name: "TV", now: start)
        #expect(first.pin.count == 4 && first.pin.allSatisfy(\.isNumber))
        #expect(receivers.issuePIN(sessionId: "s1", receiverId: "tv", name: "TV", now: start).pin == first.pin)
    }

    @Test func anExpiredPINCannotBeApproved() {
        let receivers = StageReceivers(file: nil)
        let start = Date(timeIntervalSince1970: 1_000)
        _ = receivers.issuePIN(sessionId: "s1", receiverId: "tv", name: "TV", now: start)
        let later = start.addingTimeInterval(StageReceivers.pinLifetime + 1)
        #expect(receivers.approve(sessionId: "s1", now: later) == nil)
    }

    @Test func approvalReturnsATokenThatAuthorizesOnlyItsReceiver() {
        let receivers = StageReceivers(file: nil)
        let now = Date()
        _ = receivers.issuePIN(sessionId: "s1", receiverId: "tv", name: "TV", now: now)
        let token = receivers.approve(sessionId: "s1", now: now)
        #expect(token != nil)
        #expect(receivers.isAuthorized(receiverId: "tv", token: token ?? ""))
        #expect(!receivers.isAuthorized(receiverId: "tv", token: "wrong-token-that-is-not-approved-anywhere"))
        #expect(!receivers.isAuthorized(receiverId: "other", token: token ?? ""))
    }

    @Test func theHostStoresOnlyAHashOfTheToken() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let receivers = StageReceivers(file: file)
        let now = Date()
        _ = receivers.issuePIN(sessionId: "s1", receiverId: "tv", name: "TV", now: now)
        let token = try #require(receivers.approve(sessionId: "s1", now: now))
        let stored = try String(contentsOf: file, encoding: .utf8)
        #expect(!stored.contains(token))
        #expect(stored.contains(StageReceivers.hash(token)))
    }

    @Test func approvedReceiversSurviveARestart() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let now = Date()
        let first = StageReceivers(file: file)
        _ = first.issuePIN(sessionId: "s1", receiverId: "tv", name: "TV", now: now)
        let token = try #require(first.approve(sessionId: "s1", now: now))
        let reloaded = StageReceivers(file: file)
        #expect(reloaded.isAuthorized(receiverId: "tv", token: token))
    }

    @Test func aCorruptFileIsIgnoredAndTheReceiversPairAgain() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("{ not a list".utf8).write(to: file)
        let receivers = StageReceivers(file: file)
        #expect(receivers.approved.isEmpty)
        #expect(!receivers.isAuthorized(receiverId: "tv", token: String(repeating: "a", count: 32)))
    }

    @Test func forgettingAReceiverRevokesItsToken() {
        let receivers = StageReceivers(file: nil)
        let now = Date()
        _ = receivers.issuePIN(sessionId: "s1", receiverId: "tv", name: "TV", now: now)
        let token = receivers.approve(sessionId: "s1", now: now) ?? ""
        receivers.forget(receiverId: "tv")
        #expect(!receivers.isAuthorized(receiverId: "tv", token: token))
    }
}
