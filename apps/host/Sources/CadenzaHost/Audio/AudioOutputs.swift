import CoreAudio
import Foundation
import os

/// An audio output from CoreAudio. `id` is the device UID, which stays the same across launches. AirPlay speakers
/// appear here while they are connected.
struct AudioOutput: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var transport: String
    var isDefault: Bool
}

/// Lists the Mac's audio outputs and selects the system default. Music plays to the default output, so selecting one
/// routes Music there. The list is cached, and it refreshes only when CoreAudio reports a change. Nothing polls.
enum AudioOutputs {
    private static let cache = OSAllocatedUnfairLock(initialState: [AudioOutput]())
    nonisolated(unsafe) private static var observers: [AudioObjectPropertyListenerBlock] = []

    /// The outputs as of the last CoreAudio change.
    static func current() -> [AudioOutput] {
        cache.withLock { $0 }
    }

    static func remoteVisible(_ outputs: [AudioOutput]) -> [AudioOutput] {
        outputs.filter { $0.transport != transportName(kAudioDeviceTransportTypeVirtual) }
    }

    /// Calls `onChange` on the main actor whenever the device list or the default output changes.
    static func startObserving(_ onChange: @escaping @MainActor () -> Void) {
        guard observers.isEmpty else { return }
        refresh()
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var address = address(selector)
            let block: AudioObjectPropertyListenerBlock = { _, _ in
                refresh()
                Task { @MainActor in onChange() }
            }
            _ = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
            observers.append(block)
        }
    }

    /// Makes the output with this UID the system default. Returns false when no such output is connected.
    static func select(_ uid: String) -> Bool {
        guard
            let device = deviceIDs().first(where: {
                hasOutput($0) && stringProperty($0, kAudioDevicePropertyDeviceUID) == uid
            })
        else { return false }
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        var value = device
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &value)
        refresh()
        return status == noErr
    }

    /// The UID of the current default output, which a selection reads back to confirm it applied.
    static func defaultUID() -> String? {
        let device = defaultDevice()
        return device == 0 ? nil : stringProperty(device, kAudioDevicePropertyDeviceUID)
    }

    static func transportName(_ value: UInt32) -> String {
        switch value {
        case kAudioDeviceTransportTypeBuiltIn: "built-in"
        case kAudioDeviceTransportTypeAirPlay: "airplay"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: "bluetooth"
        case kAudioDeviceTransportTypeUSB: "usb"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: "display"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: "virtual"
        default: "other"
        }
    }

    static func refresh() {
        let fresh = enumerate()
        cache.withLock { $0 = fresh }
    }

    private static func enumerate() -> [AudioOutput] {
        let fallback = defaultDevice()
        return deviceIDs().compactMap { device -> AudioOutput? in
            guard hasOutput(device), let uid = stringProperty(device, kAudioDevicePropertyDeviceUID) else { return nil }
            return AudioOutput(
                id: uid, name: stringProperty(device, kAudioObjectPropertyName) ?? uid,
                transport: transportName(transportType(device)), isDefault: device == fallback)
        }
    }

    private static func deviceIDs() -> [AudioObjectID] {
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices
    }

    static func defaultDevice() -> AudioObjectID {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        var device: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr ? device : 0
    }

    private static func hasOutput(_ device: AudioObjectID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func transportType(_ device: AudioObjectID) -> UInt32 {
        var address = address(kAudioDevicePropertyTransportType)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : 0
    }

    private static func stringProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        // CoreAudio returns a retained string here, so it is taken over rather than copied.
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else {
            return nil
        }
        return value.takeRetainedValue() as String
    }

    private static func address(
        _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}
