import Foundation

struct DeviceAuth: Codable, Sendable {
    var remoteId: String
    var token: String
    var lastCreditSequence: Int64
    var name: String? = nil
    var heartbeat: Bool? = nil
    var remoteVersion: String? = nil
}

struct PairRequest: Codable, Sendable {
    var secret: String? = nil
    var pin: String? = nil
    var name: String
    var heartbeat: Bool? = nil
    var remoteVersion: String? = nil
}

struct PairingInvitation: Codable, Sendable {
    var version: Int = 1
    var host: String
    var port: Int
    var fingerprint: String
    var certificateDerBase64: String
    var secret: String
    var hostName: String
    var pin: String = ""
}
