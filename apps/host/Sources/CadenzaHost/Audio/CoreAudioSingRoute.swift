import AVFAudio
import AppKit
import CoreAudio
import Foundation

/// Owns the macOS process-tap and private aggregate-device lifetime.
/// The real-time IO callback is intentionally added only with a validated separator/output graph.
final class CoreAudioSingRoute: SingCaptureRoute, @unchecked Sendable {
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var receive: (@Sendable (SingAudioBuffer) -> Void)?
    private var bufferPool: SingAudioBufferPool?
    private let ioQueue = DispatchQueue(label: "app.cadence.host.sing.audio")

    var format: SingAudioFormat? {
        guard isAvailable else { return nil }
        return defaultOutputFormat()
    }

    var isAvailable: Bool {
        musicProcessObjectID() != nil
    }

    func start(_ receive: @escaping @Sendable (SingAudioBuffer) -> Void) async throws {
        stop()
        guard let processID = musicProcessObjectID() else {
            throw SingAudioError.unavailable("Music is not running or has no capturable audio process.")
        }
        guard let singFormat = format,
            let audioFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: singFormat.sampleRate,
                channels: AVAudioChannelCount(singFormat.channelCount),
                interleaved: false)
        else {
            throw SingAudioError.unavailable("The Music output format could not be prepared.")
        }
        bufferPool = SingAudioBufferPool(format: audioFormat, capacity: 4_096)
        let tapUUID = UUID()
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: [processID])
        var createdTap = kAudioObjectUnknown
        let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &createdTap)
        guard tapStatus == noErr else { throw audioError("create process tap", status: tapStatus) }
        tapID = createdTap
        do {
            let outputUID = try defaultOutputDeviceUID()
            let description: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Cadenza Sing Output",
                kAudioAggregateDeviceUIDKey: "app.cadence.host.sing." + UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
                kAudioAggregateDeviceTapListKey: [
                    [
                        kAudioSubTapUIDKey: tapUUID.uuidString,
                        kAudioSubTapDriftCompensationKey: true,
                    ]
                ],
                kAudioAggregateDeviceIsPrivateKey: true,
            ]
            var createdAggregate = kAudioObjectUnknown
            let aggregateStatus = AudioHardwareCreateAggregateDevice(description as CFDictionary, &createdAggregate)
            guard aggregateStatus == noErr else {
                throw audioError("create aggregate audio device", status: aggregateStatus)
            }
            aggregateDeviceID = createdAggregate
            try waitUntilAlive(aggregateDeviceID)
            self.receive = receive
            var createdIOProc: AudioDeviceIOProcID?
            let ioStatus = AudioDeviceCreateIOProcIDWithBlock(
                &createdIOProc, aggregateDeviceID, ioQueue
            ) { [weak self] _, inputData, _, _, _ in
                self?.read(inputData)
            }
            guard ioStatus == noErr, let createdIOProc else {
                throw audioError("create audio IO callback", status: ioStatus)
            }
            ioProcID = createdIOProc
            let startStatus = AudioDeviceStart(aggregateDeviceID, createdIOProc)
            guard startStatus == noErr else {
                throw audioError("start aggregate audio device", status: startStatus)
            }
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        receive = nil
        bufferPool = nil
        if let ioProcID {
            if aggregateDeviceID != kAudioObjectUnknown { AudioDeviceStop(aggregateDeviceID, ioProcID) }
            if aggregateDeviceID != kAudioObjectUnknown { AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID) }
            self.ioProcID = nil
        }
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }

    private func waitUntilAlive(_ device: AudioObjectID) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        for _ in 0..<60 {
            var alive: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &alive)
            if status == noErr, alive != 0 { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw SingAudioError.unavailable("The Sing audio device did not become ready.")
    }

    private func defaultOutputDeviceUID() throws -> CFString {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var deviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let deviceStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &deviceSize, &device)
        guard deviceStatus == noErr, device != kAudioObjectUnknown else {
            throw SingAudioError.unavailable("The default output device is unavailable.")
        }
        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: CFString = "" as CFString
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        let uidStatus = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &uidSize, pointer)
        }
        guard uidStatus == noErr else { throw audioError("read output device identity", status: uidStatus) }
        guard !(uid as String).isEmpty else {
            throw SingAudioError.unavailable("The default output device has no stable identity.")
        }
        return uid
    }

    private func read(_ inputData: UnsafePointer<AudioBufferList>) {
        guard let receive, let format, let bufferPool, inputData.pointee.mNumberBuffers > 0 else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        guard let first = buffers.first, let firstData = first.mData else { return }
        let frameCount: Int
        if buffers.count >= 2 {
            frameCount = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        } else {
            frameCount = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * format.channelCount)
        }
        guard frameCount > 0, let acquired = bufferPool.acquire(frameCount: frameCount) else { return }
        let buffer = acquired.buffer
        var handedOff = false
        defer {
            if !handedOff { acquired.lease.release() }
        }
        let channels = buffer.floatChannelData!
        if buffers.count >= 2 {
            for channel in 0..<format.channelCount {
                guard channel < buffers.count else {
                    memset(channels[channel], 0, frameCount * MemoryLayout<Float>.size)
                    continue
                }
                guard let data = buffers[channel].mData else {
                    memset(channels[channel], 0, frameCount * MemoryLayout<Float>.size)
                    continue
                }
                memcpy(channels[channel], data, frameCount * MemoryLayout<Float>.size)
            }
        } else {
            let interleaved = firstData.assumingMemoryBound(to: Float.self)
            for frame in 0..<frameCount {
                for channel in 0..<format.channelCount {
                    channels[channel][frame] = interleaved[frame * format.channelCount + channel]
                }
            }
        }
        receive(
            SingAudioBuffer(format: format, frameCount: frameCount, samples: buffer, lease: acquired.lease))
        handedOff = true
    }

    private func musicProcessObjectID() -> AudioObjectID? {
        guard
            let music = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.Music"
            ).first
        else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return nil
        }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var objects = [AudioObjectID](repeating: 0, count: count)
        let readStatus = objects.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return kAudioHardwareBadObjectError }
            return AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, baseAddress
            )
        }
        guard readStatus == noErr else {
            return nil
        }
        for object in objects {
            var pidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(object, &pidAddress, 0, nil, &pidSize, &pid) == noErr else { continue }
            if pid == music.processIdentifier { return object }
        }
        return nil
    }

    private func defaultOutputFormat() -> SingAudioFormat? {
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var deviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &deviceAddress, 0, nil, &deviceSize, &device
            ) == noErr,
            device != kAudioObjectUnknown
        else { return nil }

        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: 0)
        var description = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard
            AudioObjectGetPropertyData(
                device, &formatAddress, 0, nil, &formatSize, &description
            ) == noErr,
            description.mSampleRate > 0,
            description.mChannelsPerFrame >= 2
        else { return nil }
        return SingAudioFormat(sampleRate: description.mSampleRate, channelCount: 2)
    }

    private func audioError(_ operation: String, status: OSStatus) -> SingAudioError {
        SingAudioError.unavailable(
            "Could not " + operation + " (Core Audio status " + String(status) + ").")
    }
}
