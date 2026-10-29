import Foundation

struct TransportPolicy: Codable, Equatable, Sendable {
    var mode: String
    var selection: String
    var primary: String?
    var bulk: String?
    var manual: String? = nil
    var minimumDwellMs: Int64 = 30_000
}

enum TransportPreference: String, Codable, Sendable {
    case latency
    case hostEfficiency = "host_efficiency"
    case remoteEfficiency = "remote_efficiency"
    case reliability
    case balanced
}

struct TransportConstraints: Codable, Equatable, Sendable {
    var maximumLatencyMs: Int64 = 500
    var maximumLossPercent: Double = 15
    var requireReliable: Bool = false
    var minimumReliabilityPercent: Double = 85

    enum CodingKeys: String, CodingKey { case maximumLatencyMs, maximumLossPercent, requireReliable, minimumReliabilityPercent }

    init(
        maximumLatencyMs: Int64 = 500,
        maximumLossPercent: Double = 15,
        requireReliable: Bool = false,
        minimumReliabilityPercent: Double = 85
    ) {
        self.maximumLatencyMs = maximumLatencyMs
        self.maximumLossPercent = maximumLossPercent
        self.requireReliable = requireReliable
        self.minimumReliabilityPercent = minimumReliabilityPercent
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        maximumLatencyMs = try values.decodeIfPresent(Int64.self, forKey: .maximumLatencyMs) ?? 500
        maximumLossPercent = try values.decodeIfPresent(Double.self, forKey: .maximumLossPercent) ?? 15
        requireReliable = try values.decodeIfPresent(Bool.self, forKey: .requireReliable) ?? false
        minimumReliabilityPercent = try values.decodeIfPresent(Double.self, forKey: .minimumReliabilityPercent) ?? 85
    }
}

struct HostTransportPolicy: Codable, Equatable, Sendable {
    var preference: TransportPreference = .balanced
    var constraints = TransportConstraints()
    var mode: String = "hybrid"
    var manualPath: String? = nil
    var minimumDwellMs: Int64 = 30_000

    enum CodingKeys: String, CodingKey { case preference, constraints, mode, manualPath, minimumDwellMs }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        preference = try values.decodeIfPresent(TransportPreference.self, forKey: .preference) ?? .balanced
        constraints = try values.decodeIfPresent(TransportConstraints.self, forKey: .constraints) ?? TransportConstraints()
        mode = try values.decodeIfPresent(String.self, forKey: .mode) ?? "hybrid"
        manualPath = try values.decodeIfPresent(String.self, forKey: .manualPath)
        minimumDwellMs = try values.decodeIfPresent(Int64.self, forKey: .minimumDwellMs) ?? 30_000
    }
}

struct EffectiveTransportDecision: Codable, Equatable, Sendable {
    var selected: String?
    var bulk: String?
    var reason: String
    var hostPreference: TransportPreference
    var remotePreference: TransportPreference?
    var policyMode: String = "balanced_negotiation"
    var confidence: String = "low"

    enum CodingKeys: String, CodingKey { case selected, bulk, reason, hostPreference, remotePreference, policyMode, confidence }

    init(
        selected: String?,
        bulk: String?,
        reason: String,
        hostPreference: TransportPreference,
        remotePreference: TransportPreference?,
        policyMode: String = "balanced_negotiation",
        confidence: String = "low"
    ) {
        self.selected = selected
        self.bulk = bulk
        self.reason = reason
        self.hostPreference = hostPreference
        self.remotePreference = remotePreference
        self.policyMode = policyMode
        self.confidence = confidence
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        selected = try values.decodeIfPresent(String.self, forKey: .selected)
        bulk = try values.decodeIfPresent(String.self, forKey: .bulk)
        reason = try values.decodeIfPresent(String.self, forKey: .reason) ?? ""
        hostPreference = try values.decodeIfPresent(TransportPreference.self, forKey: .hostPreference) ?? .balanced
        remotePreference = try values.decodeIfPresent(TransportPreference.self, forKey: .remotePreference)
        policyMode = try values.decodeIfPresent(String.self, forKey: .policyMode) ?? "balanced_negotiation"
        confidence = try values.decodeIfPresent(String.self, forKey: .confidence) ?? "low"
    }
}

struct TransportPathStatus: Codable, Equatable, Sendable {
    var transport: String
    var state: String
    var rssiDbm: Int?
    var rttMs: Int64?
    var lossPercent: Double?
    var throughputKbps: Int64?
    var backlogBytes: Int64?
    var energyPercentPerHour: Double?
    var energyConfidence: String?
    var sampleAgeMs: Int64?
    var p95RttMs: Int64? = nil
    var reconnects: Int64? = nil
    var activeRemotes: Int64? = nil
}

struct DevicePowerStatus: Codable, Equatable, Sendable {
    var batteryPercent: Int?
    var charging: Bool?
    var source: String?
}

struct DeviceResourceStatus: Codable, Equatable, Sendable {
    var cpuPercent: Double?
    var memoryBytes: Int64?
    var storageBytes: Int64?
}

struct SessionStatus: Codable, Equatable, Sendable {
    var reportedAtMs: Int64
    var device: String
    var power: DevicePowerStatus?
    var resources: DeviceResourceStatus?
    var paths: [TransportPathStatus]
    var effective: EffectiveTransportDecision?
    var preference: TransportPreference?
    var constraints: TransportConstraints?
}

enum TransportNegotiator {
    static func decide(
        host: HostTransportPolicy,
        remote: TransportPolicy?,
        remotePreference: TransportPreference?,
        remoteConstraints: TransportConstraints? = nil,
        paths: [TransportPathStatus]
    ) -> EffectiveTransportDecision {
        let valid = paths.filter { path in
            guard path.state == "connected" || path.state == "degraded" else { return false }
            let constraints = remoteConstraints.map {
                TransportConstraints(
                    maximumLatencyMs: min(host.constraints.maximumLatencyMs, $0.maximumLatencyMs),
                    maximumLossPercent: min(host.constraints.maximumLossPercent, $0.maximumLossPercent),
                    requireReliable: host.constraints.requireReliable || $0.requireReliable,
                    minimumReliabilityPercent: max(host.constraints.minimumReliabilityPercent, $0.minimumReliabilityPercent))
            } ?? host.constraints
            if let rtt = path.rttMs { guard rtt <= constraints.maximumLatencyMs else { return false } }
            if let loss = path.lossPercent {
                guard loss <= constraints.maximumLossPercent else { return false }
                guard 100 - loss >= constraints.minimumReliabilityPercent else { return false }
            }
            guard path.transport == "lan" || path.transport == "wifi" || path.transport == "ethernet" || path.transport == "ble" else { return false }
            return true
        }
        guard !valid.isEmpty else {
            return EffectiveTransportDecision(
                selected: nil,
                bulk: nil,
                reason: "No path satisfies Host safety limits.",
                hostPreference: host.preference,
                remotePreference: remotePreference,
                policyMode: host.manualPath == nil ? "balanced_negotiation" : "manual",
                confidence: "low")
        }
        let constrained = valid.filter { path in
            guard host.mode == "hybrid" else {
                return host.mode == "ble_only" ? path.transport == "ble" : ["lan", "wifi", "ethernet"].contains(path.transport)
            }
            if let remote {
                switch remote.mode {
                case "ble_only": return path.transport == "ble"
                case "lan_only": return ["lan", "wifi", "ethernet"].contains(path.transport)
                default: break
                }
            }
            return true
        }
        let candidates = constrained.isEmpty ? valid : constrained
        let selected = host.manualPath.flatMap { manual in candidates.first { $0.transport == manual } } ?? candidates.max {
            score($0, host: host.preference, remote: remotePreference)
                < score($1, host: host.preference, remote: remotePreference)
        }
        let bulk = remote?.bulk == "ble" ? "ble" : "lan"
        let confidence = selected?.energyConfidence ?? "low"
        return EffectiveTransportDecision(
            selected: selected?.transport,
            bulk: bulk,
            reason: reason(selected, host: host, remote: remotePreference),
            hostPreference: host.preference,
            remotePreference: remotePreference,
            policyMode: host.manualPath == nil ? "balanced_negotiation" : "manual",
            confidence: confidence)
    }

    private static func score(
        _ path: TransportPathStatus,
        host: TransportPreference,
        remote: TransportPreference?
    ) -> Double {
        let latency = 1 - min(Double(path.p95RttMs ?? path.rttMs ?? 500) / 500, 1)
        let reconnectPenalty = min(Double(path.reconnects ?? 0) / 20, 1)
        let reliability = max(0, 1 - min((path.lossPercent ?? 100) / 100, 1) - reconnectPenalty * 0.25)
        let energy = 1 - min((path.energyPercentPerHour ?? 1) / 5, 1)
        func weight(_ preference: TransportPreference) -> (Double, Double, Double) {
            switch preference {
            case .latency: return (0.7, 0.2, 0.1)
            case .reliability: return (0.2, 0.7, 0.1)
            case .hostEfficiency, .remoteEfficiency: return (0.2, 0.2, 0.6)
            case .balanced: return (0.4, 0.3, 0.3)
            }
        }
        let a = weight(host), b = remote.map(weight)
        let divisor = b == nil ? 1.0 : 2.0
        let values = [
            (a.0 + (b?.0 ?? a.0)) / divisor,
            (a.1 + (b?.1 ?? a.1)) / divisor,
            (a.2 + (b?.2 ?? a.2)) / divisor,
        ]
        return values[0] * latency + values[1] * reliability + values[2] * energy
    }

    private static func reason(
        _ path: TransportPathStatus?,
        host: HostTransportPolicy,
        remote: TransportPreference?
    ) -> String {
        guard let path else { return "No healthy path." }
        let loss = path.lossPercent.map { String(format: "%.1f%% loss", $0) } ?? "unknown loss"
        return "\(path.transport.uppercased()) selected; \(loss) is within Host limits. "
            + "Host policy: \(host.preference.rawValue); Remote policy: \(remote?.rawValue ?? "balanced")."
    }
}
