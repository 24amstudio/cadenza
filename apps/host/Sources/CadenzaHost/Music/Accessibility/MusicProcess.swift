import AppKit
import Darwin
import Foundation

/// Finds Music's process. NSRunningApplication's bundle lookup can omit a running Music for a moment after Music changes
/// state, so a miss is answered from the process table, and then from the last known process while it is still alive.
enum MusicProcess {
    static let bundleId = "com.apple.Music"
    private static let executableSuffix = "/Music.app/Contents/MacOS/Music"

    /// A fresh lookup wins. With none, the last known process stands in while it is still running, and nil means Music
    /// is not running.
    static func resolve(lookup: pid_t?, lastKnown: pid_t?, isRunning: (pid_t) -> Bool) -> pid_t? {
        if let lookup { return lookup }
        guard let lastKnown, isRunning(lastKnown) else { return nil }
        return lastKnown
    }

    static func lookup() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.processIdentifier
            ?? scanProcessTable()
    }

    /// Reads the process table directly, so it does not depend on the workspace's running-application list.
    static func isRunning(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        var path = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &path, UInt32(path.count))
        guard length > 0 else { return false }
        return String(decoding: path.prefix(Int(length)), as: UTF8.self).hasSuffix(executableSuffix)
    }

    private static func scanProcessTable() -> pid_t? {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return nil }
        return pids.prefix(Int(filled)).first(where: isRunning)
    }
}
