import CoreGraphics
import Foundation

/// Whether the Mac's screen is locked. A locked display answers no Accessibility request, so each request would wait out
/// its timeout. The session is read at each check, so a lock or unlock is never missed.
enum ScreenLock {
    static var isLocked: Bool {
        isLocked(session: CGSessionCopyCurrentDictionary() as? [String: Any])
    }

    static func isLocked(session: [String: Any]?) -> Bool {
        (session?["CGSSessionScreenIsLocked"] as? Bool) == true
    }
}
