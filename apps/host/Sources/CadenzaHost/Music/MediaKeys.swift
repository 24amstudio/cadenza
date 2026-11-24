import AppKit
import CoreGraphics

/// The system media keys, as the keyboard's HID codes (NX_KEYTYPE_PLAY, NX_KEYTYPE_NEXT, NX_KEYTYPE_PREVIOUS).
enum MediaKey: Int {
    case playPause = 16
    case next = 17
    case previous = 18

    /// The data word of a media-key system event: the key code in the high bits, then the key state (0xA down, 0xB up).
    static func data(_ key: MediaKey, keyDown: Bool) -> Int {
        (key.rawValue << 16) | ((keyDown ? 0xA : 0xB) << 8)
    }
}

/// Posts media-key presses the way the keyboard does. The posted key reaches whichever app the system treats as now
/// playing, so it can act on another app. Callers must confirm Music is the target before they post.
enum MediaKeys {
    static func post(_ key: MediaKey) {
        for keyDown in [true, false] {
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                context: nil, subtype: 8, data1: MediaKey.data(key, keyDown: keyDown), data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
