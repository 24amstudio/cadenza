import Foundation

struct ClockSample: Codable, Sendable {
    var sentAtRemoteMs: Int64
    var receivedAtHostMs: Int64? = nil
    var sentAtHostMs: Int64? = nil
}
