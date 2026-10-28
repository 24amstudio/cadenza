import Foundation

func formatDuration(_ milliseconds: Int64?) -> String {
    guard let milliseconds else { return "Unknown" }
    let seconds = max(0, milliseconds / 1_000)
    return "\(seconds / 60):" + String(format: "%02lld", seconds % 60)
}
