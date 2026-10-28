import Foundation

struct HostCacheStats: Sendable {
    let bytes: Int64
    let entries: Int
    let limitBytes: Int64
    var fractionUsed: Double { limitBytes == 0 ? 0 : Double(bytes) / Double(limitBytes) }
}
