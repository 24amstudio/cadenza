import Foundation
import Network

@MainActor
final class SSDPResponder {
    nonisolated static let serviceType = "urn:cadenza:host:1"
    private static let multicastAddress = "239.255.255.250"
    private static let multicastPort: UInt16 = 1900

    private let queue = DispatchQueue(label: "app.cadenza.ssdp", qos: .utility)
    private var group: NWConnectionGroup?

    func start(hostId: String, address: String, port: UInt16) {
        stop()
        guard let multicastPort = NWEndpoint.Port(rawValue: Self.multicastPort),
            let servicePort = NWEndpoint.Port(rawValue: port),
            !address.isEmpty
        else { return }
        do {
            let multicast = try NWMulticastGroup(for: [
                .hostPort(
                    host: NWEndpoint.Host(Self.multicastAddress),
                    port: multicastPort)
            ])
            let group = NWConnectionGroup(with: multicast, using: .udp)
            group.setReceiveHandler(
                maximumMessageSize: 4_096,
                rejectOversizedMessages: true
            ) { message, content, _ in
                guard let content else { return }
                let response = Self.response(
                    for: content,
                    hostId: hostId,
                    location: "https://\(address):\(servicePort.rawValue)/")
                guard let response else { return }
                message.reply(content: response)
            }
            group.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    NSLog("Cadenza SSDP responder stopped: %@", error.localizedDescription)
                }
            }
            self.group = group
            group.start(queue: queue)
        } catch {
            NSLog("Cadenza SSDP responder unavailable: %@", error.localizedDescription)
        }
    }

    func stop() {
        group?.cancel()
        group = nil
    }

    nonisolated static func response(for data: Data, hostId: String, location: String) -> Data? {
        guard requestMatches(data),
            hostId.range(of: "^[0-9a-f-]{36}$", options: .regularExpression) != nil,
            location.hasPrefix("https://"),
            (location.unicodeScalars.allSatisfy { $0.value >= 0x20 })
        else { return nil }
        let lines = [
            "HTTP/1.1 200 OK",
            "CACHE-CONTROL: max-age=120",
            "EXT:",
            "LOCATION: \(location)",
            "SERVER: Cadenza Host/1 UPnP/1.1",
            "ST: \(serviceType)",
            "USN: uuid:\(hostId)::\(serviceType)",
            "HOST-ID: \(hostId)",
            "",
            "",
        ]
        return Data(lines.joined(separator: "\r\n").utf8)
    }

    nonisolated static func requestMatches(_ data: Data) -> Bool {
        guard data.count <= 4_096,
            let text = String(data: data, encoding: .utf8)
        else { return false }
        let lines = text.split(whereSeparator: \.isNewline)
        let requestLine = lines.first?.split(separator: " ") ?? []
        guard requestLine.count >= 2, requestLine[0] == "M-SEARCH", requestLine[1] == "*" else {
            return false
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                headers[parts[0].trimmingCharacters(in: .whitespaces).lowercased()] =
                    parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        guard headers["man"]?.lowercased() == "\"ssdp:discover\"" else { return false }
        return headers["st"]?.lowercased() == serviceType.lowercased()
    }
}
