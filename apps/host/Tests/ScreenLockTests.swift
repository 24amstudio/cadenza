import Foundation
import Testing

@testable import CadenzaHost

struct ScreenLockTests {
    @Test func aLockedSessionIsRecognisedAndAnyOtherSessionIsNot() {
        #expect(ScreenLock.isLocked(session: ["CGSSessionScreenIsLocked": true]))
        #expect(!ScreenLock.isLocked(session: ["CGSSessionScreenIsLocked": false]))
        #expect(!ScreenLock.isLocked(session: ["UserName": "someone"]))
        #expect(!ScreenLock.isLocked(session: nil))
    }
}
