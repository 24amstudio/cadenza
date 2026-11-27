import AVFAudio
import AppKit
import CoreAudio
import Foundation

/// Owns the macOS process-tap and private aggregate-device lifetime.
/// The real-time IO callback is intentionally added only with a validated separator/output graph.
final class CoreAudioSingRoute: SingCaptureRoute, @unchecked Sendable {
    private let muteWhenTapped: Bool
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var receive: (@Sendable (SingAudioBuffer) -> Void)?
    private var bufferPool: SingAudioBufferPool?
    private var ring: RealtimeCaptureRing?
    private let ioQueue = DispatchQueue(label: "app.cadence.host.sing.audio", qos: .userInteractive)
    private let consumerQueue = DispatchQueue(label: "app.cadence.host.sing.capture", qos: .userInteractive)

    init(muteWhenTapped: Bool = true) {
        self.muteWhenTapped = muteWhenTapped
    }

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
        let pool = SingAudioBufferPool(format: audioFormat, capacity: 4_096)
        guard let ring = RealtimeCaptureRing(channelCount: singFormat.channelCount, frameCapacity: 4_096) else {
            throw SingAudioError.unavailable("The capture ring could not be prepared.")
        }
        bufferPool = pool
        self.ring = ring
        let tapUUID = UUID()
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: [processID])
        tapDescription.uuid = tapUUID
        tapDescription.name = "Cadenza Sing Music Tap"
        tapDescription.isPrivate = true
        tapDescription.isMixdown = true
        tapDescription.isMono = false
        tapDescription.muteBehavior = muteWhenTapped ? .mutedWhenTapped : .unmuted
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
            requestBufferFrames(aggregateDeviceID, frames: 512)
            self.receive = receive
            // The consumer and the IOProc each keep their own strong references, so `stop` can clear this route's
            // state on another thread without racing either of them.
            consumerQueue.async {
                Self.drain(ring: ring, format: singFormat, pool: pool, receive: receive)
            }
            var createdIOProc: AudioDeviceIOProcID?
            let ioStatus = AudioDeviceCreateIOProcIDWithBlock(
                &createdIOProc, aggregateDeviceID, ioQueue
            ) { _, inputData, inputTime, _, _ in
                _ = ring.write(inputData, hostTime: inputTime.pointee.mHostTime)
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
        ring?.stop()
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
        ring = nil
        bufferPool = nil
    }

    /// Asks the aggregate device for 512-frame blocks, which is 10.67 ms at 48 kHz. A device that refuses keeps its
    /// own size, so this is best effort and never blocks the capture.
    private func requestBufferFrames(_ device: AudioObjectID, frames: UInt32) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value = frames
        _ = AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
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

    /// The realtime IOProc used to live here; it now writes straight into the ring, so nothing on this route is read
    /// from the audio thread.
    ///
    /// Drains captured blocks on the user-interactive consumer queue, where pooled buffers and receivers may allocate.
    /// It owns its ring, pool, format and receiver, so it keeps running until `ring.stop()` is called.
    private static func drain(
        ring: RealtimeCaptureRing,
        format: SingAudioFormat,
        pool: SingAudioBufferPool,
        receive: @escaping @Sendable (SingAudioBuffer) -> Void
    ) {
        while !ring.isStopped {
            _ = ring.waitForFrames(timeout: .now() + .milliseconds(100))
            while let read = ring.read() {
                deliver(read, from: ring, format: format, pool: pool, receive: receive)
                ring.release(read)
            }
        }
    }

    private static func deliver(
        _ read: RealtimeCaptureRing.Read,
        from ring: RealtimeCaptureRing,
        format: SingAudioFormat,
        pool: SingAudioBufferPool,
        receive: (SingAudioBuffer) -> Void
    ) {
        guard let acquired = pool.acquire(frameCount: read.frameCount),
            let channels = acquired.buffer.floatChannelData
        else { return }
        for channel in 0..<read.channelCount {
            memcpy(
                channels[channel], ring.samples(for: read, channel: channel),
                read.frameCount * MemoryLayout<Float>.size)
        }
        receive(
            SingAudioBuffer(
                format: format, frameCount: read.frameCount, samples: acquired.buffer, lease: acquired.lease,
                hostTime: read.hostTime))
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
        guard
            AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else {
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
