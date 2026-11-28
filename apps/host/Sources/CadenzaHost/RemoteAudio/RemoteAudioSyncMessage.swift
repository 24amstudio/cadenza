import Foundation

enum RemoteAudioSyncMessage {
    static func make(
        telemetry: RemoteAudioTelemetry, nowUs: UInt64, clock: RemoteClockEstimator, jitterBufferMs: Double,
        droppedStaleFrames60s: Int
    ) -> [String: Any] {
        let latest = clock.latest
        return [
            "version": 1,
            "type": "REMOTE_AUDIO_SYNC",
            "streamMode": telemetry.streamMode.rawValue,
            "calibrationState": telemetry.calibrationState,
            "electronicOffsetMs": telemetry.electronicOffsetMs,
            "acousticOffsetMs": 0,
            "clockOffsetUs": microseconds(clock.offsetUs(atHostUs: nowUs)),
            "clockDriftPpm": clock.driftPpm,
            "jitterBufferMs": jitterBufferMs,
            "droppedStaleFrames60s": droppedStaleFrames60s,
            "linkHealthy": telemetry.linkHealthy,
            "transmitting": telemetry.transmitting,
            "quality": telemetry.quality.wireName,
            "qualityReason": telemetry.qualityReason.rawValue,
            "networkRttMs": milliseconds(latest?.rttUs),
            "processingRttMs": milliseconds(latest?.processingUs),
        ]
    }

    private static func microseconds(_ value: Int64?) -> Any {
        guard let value else { return NSNull() }
        return NSNumber(value: value)
    }

    private static func milliseconds(_ microseconds: Int64?) -> Any {
        guard let microseconds else { return NSNull() }
        return Double(microseconds) / 1_000
    }
}
