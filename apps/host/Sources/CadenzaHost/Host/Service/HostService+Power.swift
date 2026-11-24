import Foundation

extension HostService {
    /// Keeps the Mac awake while Music plays or an authenticated Remote is connected.
    func refreshSleepAssertion() {
        let remoteConnected = network.peers.values.contains { $0.authenticated }
        sleepAssertion.update(active: queue.isPlaying || remoteConnected)
    }

    /// Publishes a changed thermal budget to Remotes in the next state snapshot.
    func setHostBudget(_ budget: HostOperatingBudget) {
        guard budget != publishedState.hostBudget else { return }
        publishedState.hostBudget = budget
        queue.publish()
    }
}
