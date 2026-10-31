import SwiftUI

struct RemoteStatusRow: View {
    let remote: PairedRemote

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label(remote.name, systemImage: "ipad.and.iphone")
                    .font(.headline)
                Spacer()
                Text(remote.revoked ? "Unpaired" : connectionLabel)
                    .foregroundStyle(remote.revoked ? .secondary : .primary)
            }
            if let status = remote.status {
                HStack(spacing: 12) {
                    if let battery = status.power?.batteryPercent {
                        Label(
                            status.power?.charging == true ? "\(battery)% charging" : "\(battery)%",
                            systemImage: status.power?.charging == true ? "battery.100.bolt" : "battery.75")
                    }
                    ForEach(Array(status.paths.enumerated()), id: \.offset) { _, path in
                        Label(pathLabel(path), systemImage: pathIcon(path))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if let estimate = energySummary(status.paths) {
                    Text(estimate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let decision = status.effective {
                    Text("Effective: \(decision.selected?.uppercased() ?? "Offline") · \(decision.reason)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !remote.revoked {
                Text("Waiting for this Remote to connect")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private var connectionLabel: String {
        remote.status == nil ? "Paired" : "Connected"
    }

    private func pathLabel(_ path: TransportPathStatus) -> String {
        let name = path.transport == "ble" ? "Bluetooth" : path.transport.uppercased()
        if let rtt = path.rttMs { return "\(name) \(rtt) ms" }
        return name
    }

    private func pathIcon(_ path: TransportPathStatus) -> String {
        switch path.transport {
        case "ble": return "wave.3.right"
        case "ethernet": return "cable.connector"
        default: return "wifi"
        }
    }

    private func energySummary(_ paths: [TransportPathStatus]) -> String? {
        let estimates = paths.compactMap { path -> String? in
            guard let energy = path.energyPercentPerHour else { return nil }
            let name = path.transport == "ble" ? "Bluetooth" : path.transport.uppercased()
            let confidence = path.energyConfidence.map { "\($0) confidence" } ?? "estimated"
            return "\(name) ~\(energy.formatted(.number.precision(.fractionLength(1))))%/h (\(confidence))"
        }
        return estimates.isEmpty ? nil : estimates.joined(separator: " · ")
    }
}
