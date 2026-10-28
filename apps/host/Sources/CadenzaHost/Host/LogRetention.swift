import Foundation

enum HostLogRetention {
    static var days: Int {
        get { min(max(UserDefaults.standard.integer(forKey: "systemLogRetentionDays"), 7), 30) }
        set { UserDefaults.standard.set(min(max(newValue, 7), 30), forKey: "systemLogRetentionDays") }
    }
}
