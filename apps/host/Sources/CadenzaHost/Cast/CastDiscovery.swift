import Foundation
import Network
import Observation

/// Browses for Google Cast devices on the local network and lists them with what their capability record reports.
/// Discovery confers no trust. It only lists devices. The Host starts it once and it runs while the Host runs.
@Observable
@MainActor
final class CastDiscovery {
    struct Device: Equatable, Sendable {
        let name: String
        let display: CastDisplay
    }

    private(set) var devices: [Device] = []
    @ObservationIgnored var onChange: (([Device]) -> Void)?
    @ObservationIgnored private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: "_googlecast._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap { result -> Device? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                var capabilities: String?
                if case .bonjour(let record) = result.metadata { capabilities = record.dictionary["ca"] }
                return Device(name: name, display: CastDisplay.fromCapabilities(capabilities))
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
    }
}
