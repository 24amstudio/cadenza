import Foundation

/// Stops a failing self-update from restarting Host forever. A target build gets two install attempts. After that it is
/// left alone until a newer build is published, and a successful install clears the record.
enum SelfUpdateLoopGuard {
    static let attemptLimit = 2
    private static let key = "cadenza.selfUpdate.attempts"

    struct Record: Codable, Equatable {
        var targetBuild: Int64
        var attempts: Int
    }

    static func allowsAttempt(for target: Int64, record: Record?) -> Bool {
        guard let record, record.targetBuild == target else { return true }
        return record.attempts < attemptLimit
    }

    static func recordingAttempt(for target: Int64, after record: Record?) -> Record {
        guard let record, record.targetBuild == target else { return Record(targetBuild: target, attempts: 1) }
        return Record(targetBuild: target, attempts: record.attempts + 1)
    }

    /// Keeps the record only while the running build is still older than the target it was installing.
    static func settled(_ record: Record?, runningBuild: Int64) -> Record? {
        guard let record, record.targetBuild > runningBuild else { return nil }
        return record
    }

    static func load(_ defaults: UserDefaults = .standard) -> Record? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    static func save(_ record: Record?, _ defaults: UserDefaults = .standard) {
        guard let record, let data = try? JSONEncoder().encode(record) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}
