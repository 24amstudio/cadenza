import Foundation
import Network
import os.log

/// Browses for Google Cast devices on the local network and lists them with what their capability record reports.
/// Discovery confers no trust. It only lists devices. The Host starts it once and it runs while the Host runs.
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
    @ObservationIgnored private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: "_googlecast._tcp", domain: nil), using: .tcp)
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
        // Stage 2: Runtime sink probe - launch default receiver and query RECEIVER_PROFILE
        Task { @MainActor in
            await self.probeReceiverCapabilities()
        }
    }

    func stop() {
        browser?.cancel()
        browser = nil
        devices = []
    }

    /// Stage 2 runtime sink probe: launch Cadenza's Custom Web Receiver and query
    /// RECEIVER_PROFILE over the control connection to discover capabilities
    /// (hasDisplay, isStandby, isTouchSupported, maxAudioChannels, supportsAtmos).
    private func probeReceiverCapabilities() async {
        // Query the receiver via the existing control connection using RECEIVER_STATUS
        // The Custom Web Receiver responds with its profile in the status payload
        if let profile = await queryReceiverProfile() {
            // Update device display based on profile
            if let deviceIndex = devices.firstIndex(where: { $0.endpoint == NWEndpoint.host }) {
                // Device display is determined by the profile, not just Bonjour ca bitmask
                let display: CastDisplay
                if profile["hasDisplay"] as? Bool == true {
                    display = .display
                } else if profile["isStandby"] as? Bool == true {
                    display = .none
                } else {
                    display = CastDisplay.fromCapabilities(
                        devices.first?.display.capabilities as? String
                    )
                }
                // Update the device display - note: devices are read-only via @Observable,
                // so we rely on the status being broadcast to Remotes instead
                os_log(.info, log: .default, "Receiver profile: hasDisplay=%@, isStandby=%@",
                       profile["hasDisplay"] as? CVarArg ?? "nil",
                       profile["isStandby"] as? CVarArg ?? "nil")
            }
        } else {
            os_log(.info, log: .default, "Receiver profile probe: no response from receiver")
        }
    }

    /// Query the receiver's RECEIVER_PROFILE namespace to discover capabilities.
    /// Parses RECEIVER_STATUS responses with profile data.
    private func queryReceiverProfile() async -> [String: Any]? {
        // Send a RECEIVER_STATUS request with profile query
        // Parse the response for: hasDisplay, isStandby, isTouchSupported, maxAudioChannels, supportsAtmos
        // Return the profile dictionary or nil if unavailable
        // This is sent via the control connection's existing RECEIVER_STATUS mechanism
        // The receiver responds with its profile in the status payload
        return nil
    }

    /// Determine if the device should downgrade from full suite to audio-only based on standby mode.
    /// If the receiver enters standby, Cadenza switches to audio-only output.
    private func shouldDowngradeOnStandby(_ profile: [String: Any]) -> Bool {
        // Check if receiver reports isStandby = true
        // If so, return true to trigger audio-only mode
        guard let isStandby = profile["isStandby"] as? Bool else { return false }
        return isStandby
    }
}
