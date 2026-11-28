import CoreAudio
import Foundation

enum HostOutputLatency {
    struct Measurement: Equatable, Sendable {
        let frames: Int
        let sampleRate: Double
    }

    static func defaultOutput() -> Measurement? {
        let device = AudioOutputs.defaultDevice()
        guard device != 0,
            let latency = uint32(device, kAudioDevicePropertyLatency, scope: kAudioObjectPropertyScopeOutput),
            let safety = uint32(device, kAudioDevicePropertySafetyOffset, scope: kAudioObjectPropertyScopeOutput)
        else { return nil }
        let stream = firstOutputStream(of: device).flatMap {
            uint32($0, kAudioStreamPropertyLatency, scope: kAudioObjectPropertyScopeGlobal)
        }
        let rate = float64(device, kAudioDevicePropertyNominalSampleRate, scope: kAudioObjectPropertyScopeGlobal)
        return Measurement(
            frames: Int(latency) + Int(safety) + Int(stream ?? 0),
            sampleRate: rate.flatMap { $0 > 0 ? $0 : nil } ?? 48_000)
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

    private static func float64(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope
    ) -> Float64? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var value: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
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
