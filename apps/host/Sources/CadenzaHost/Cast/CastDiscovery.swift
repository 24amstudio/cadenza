import Foundation
import Network

/// Browses for Google Cast devices on the local network and lists them with what their capability record reports.
/// Discovery confers no trust. It only lists devices. The Host starts it once and it runs while the Host runs.
/// Display capability comes only from the mDNS `ca` record. Standard Cast devices do not report a profile, so the Host
/// never launches an app to probe one.
@Observable
@MainActor
final class CastDiscovery {
    struct Device: Equatable, Sendable {
        let name: String
        let display: CastDisplay
        /// The Bonjour endpoint, which the control connection uses to reach the device's TLS port.
        let endpoint: NWEndpoint
    }

    private(set) var devices: [Device] = []
    @ObservationIgnored var onChange: (([Device]) -> Void)?
    /// Called when the browse starts waiting or fails, with the reason, so a blocked browse is not silent.
    @ObservationIgnored var onFailure: ((String) -> Void)?
    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var lastProblem: String?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: "_googlecast._tcp", domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            let problem: String? =
                switch state {
                case .waiting(let error): "Google Cast discovery is waiting: \(error.localizedDescription)"
                case .failed(let error): "Google Cast discovery failed: \(error.localizedDescription)"
                default: nil
                }
            Task { @MainActor in self?.browserProblemChanged(problem) }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap { result -> Device? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                var capabilities: String?
                if case .bonjour(let record) = result.metadata { capabilities = record.dictionary["ca"] }
                return Device(
                    name: name, display: CastDisplay.fromCapabilities(capabilities), endpoint: result.endpoint)
            }
            .sorted { $0.name < $1.name }
            Task { @MainActor in
                self?.devices = found
                self?.onChange?(found)
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        devices = []
        lastProblem = nil
    }

    /// Reports a problem once, when it appears. A browse that recovers clears it, so a later failure is reported again.
    private func browserProblemChanged(_ problem: String?) {
        guard problem != lastProblem else { return }
        lastProblem = problem
        if let problem { onFailure?(problem) }
    }
}
