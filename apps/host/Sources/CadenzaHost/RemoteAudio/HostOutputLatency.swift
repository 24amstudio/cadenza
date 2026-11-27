import CoreAudio
import Foundation

/// The electronic latency of the Host's default output, in frames: the device's latency, its safety offset, and the
/// first output stream's latency. Stage 1 of the silent calibration reads it on connect. A device that reports none of
/// these returns nil, and the calibration then stays degraded rather than guessing.
enum HostOutputLatency {
    static func defaultOutputFrames() -> Int? {
        let device = AudioOutputs.defaultDevice()
        guard device != 0,
            let latency = uint32(device, kAudioDevicePropertyLatency, scope: kAudioObjectPropertyScopeOutput),
            let safety = uint32(device, kAudioDevicePropertySafetyOffset, scope: kAudioObjectPropertyScopeOutput)
        else { return nil }
        let stream = firstOutputStream(of: device).flatMap {
            uint32($0, kAudioStreamPropertyLatency, scope: kAudioObjectPropertyScopeGlobal)
        }
        return Int(latency) + Int(safety) + Int(stream ?? 0)
    }

    private static func uint32(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func firstOutputStream(of device: AudioObjectID) -> AudioStreamID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
            size >= UInt32(MemoryLayout<AudioStreamID>.size)
        else { return nil }
        var streams = [AudioStreamID](repeating: 0, count: Int(size) / MemoryLayout<AudioStreamID>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &streams) == noErr else { return nil }
        return streams.first
    }
}
