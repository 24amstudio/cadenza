import Foundation
import Testing

@testable import CadenzaHost

struct MediaKeysTests {
    @Test func aPlayPausePressPacksItsKeyCodeAndStateIntoTheEventWord() {
        #expect(MediaKey.data(.playPause, keyDown: true) == 0x0010_0A00)
        #expect(MediaKey.data(.playPause, keyDown: false) == 0x0010_0B00)
        #expect(MediaKey.data(.next, keyDown: true) == 0x0011_0A00)
        #expect(MediaKey.data(.previous, keyDown: false) == 0x0012_0B00)
    }
}
