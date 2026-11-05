import Foundation
import Testing

@testable import CadenzaHost

// Several Bluetooth Remotes share one Host. Each fake Remote records the frames it is handed, and can refuse them the
// way CoreBluetooth does when its queue is full, or fail outright.
@MainActor
struct NetworkRemoteFanoutTests {
    private final class FakeRemote {
        var received: [Data] = []
        var result: TransportSendResult = .accepted
        var cancelled = false
    }

    private func connect(_ network: NetworkService, count: Int) -> [UUID: FakeRemote] {
        var remotes: [UUID: FakeRemote] = [:]
        for _ in 0..<count {
            let central = UUID()
            let remote = FakeRemote()
            remotes[central] = remote
            network.acceptBluetooth(
                centralID: central,
                send: { data in
                    guard remote.result == .accepted else { return remote.result }
                    remote.received.append(data)
                    return .accepted
                },
                cancel: { remote.cancelled = true })
        }
        for peer in network.peers.values {
            peer.authenticated = true
            peer.supportsHeartbeat = true
        }
        return remotes
    }

    private func heartbeat(_ epoch: String) -> Frame {
        Frame(type: "heartbeat", hostEpoch: epoch)
    }

    @Test @MainActor func fiveRemotesEachReceiveTheSameFrameOnce() {
        let network = NetworkService()
        let remotes = connect(network, count: 5)

        network.broadcast(heartbeat("epoch-1"))

        let frames = remotes.values.map(\.received)
        #expect(frames.allSatisfy { $0.count == 1 })
        #expect(Set(frames.map { $0[0] }).count == 1)
        #expect(String(decoding: frames[0][0], as: UTF8.self).contains("epoch-1"))
    }

    @Test @MainActor func aRefusingRemoteHoldsOnlyItsLatestFrameAndTheOthersKeepGoing() {
        let network = NetworkService()
        let remotes = connect(network, count: 5)
        let slowCentral = remotes.keys.sorted { $0.uuidString < $1.uuidString }[0]
        let slow = remotes[slowCentral]!
        slow.result = .full

        network.broadcast(heartbeat("epoch-1"))
        network.broadcast(heartbeat("epoch-2"))
        network.broadcast(heartbeat("epoch-3"))

        #expect(slow.received.isEmpty)
        for (central, remote) in remotes where central != slowCentral {
            #expect(remote.received.count == 3)
        }
        #expect(network.peers.count == 5)

        slow.result = .accepted
        network.drainedBluetooth(slowCentral)

        // Only the newest frame is delivered. Older ones were superseded, not queued behind it.
        #expect(slow.received.count == 1)
        #expect(String(decoding: slow.received[0], as: UTF8.self).contains("epoch-3"))
        #expect(network.peers.count == 5)
    }

    @Test @MainActor func aRemoteThatFailsIsDisconnectedWithoutAffectingTheOthers() {
        let network = NetworkService()
        let remotes = connect(network, count: 5)
        let failingCentral = remotes.keys.sorted { $0.uuidString < $1.uuidString }[0]
        let failing = remotes[failingCentral]!
        failing.result = .failed

        network.broadcast(heartbeat("epoch-1"))

        #expect(failing.cancelled)
        #expect(network.peers.count == 4)
        for (central, remote) in remotes where central != failingCentral {
            #expect(remote.received.count == 1)
        }
    }
    // Media queued before a state update must not hold that update back. The state goes first, then the media resumes.
    @Test @MainActor func aStateUpdateIsNotHeldBehindQueuedMedia() {
        let network = NetworkService()
        let remotes = connect(network, count: 1)
        let central = remotes.keys.first!
        let remote = remotes[central]!
        let peer = network.peers.values.first!
        remote.result = .full

        for index in 0..<3 {
            network.send(Frame(type: "artwork.chunk", requestId: "art-\(index)"), to: peer)
        }
        network.send(heartbeat("epoch-1"), to: peer)
        remote.result = .accepted
        network.drainedBluetooth(central)

        let order = remote.received.map { String(decoding: $0, as: UTF8.self) }
        #expect(order.count == 4)
        #expect(order[0].contains("epoch-1"))
        #expect(order[1].contains("art-0") && order[3].contains("art-2"))
    }
}
