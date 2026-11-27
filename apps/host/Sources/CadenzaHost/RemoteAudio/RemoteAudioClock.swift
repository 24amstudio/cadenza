import Foundation

/// The clock for Remote audio playout times and clock pings. It counts microseconds of `mach_continuous_time`, which
/// keeps running through sleep, so a playout instant means the same thing on every frame.
enum RemoteAudioClock {
    static func nowUs() -> UInt64 {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let nanoseconds = mach_continuous_time() * UInt64(timebase.numer) / UInt64(timebase.denom)
        return nanoseconds / 1_000
    }

    /// The continuous-clock microsecond at which a device sample time occurs. Device times are mach absolute time, so this
    /// applies the sleep offset `machAbsoluteTime(forPlayoutUs:)` removes, in the other direction.
    static func continuousUs(forHostTime hostTime: UInt64) -> UInt64 {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return continuousMicroseconds(hostTicks: hostTime, sleepTicks: sleepTicks(), timebase: timebase)
    }

    /// The mach absolute time at which a playout instant on this clock occurs. `AVAudioTime` schedules in that domain,
    /// which differs from the continuous clock only by the time the Mac has slept.
    static func machAbsoluteTime(forPlayoutUs playoutUs: UInt64) -> UInt64 {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let continuousTicks = playoutUs * 1_000 * UInt64(timebase.denom) / UInt64(timebase.numer)
        return continuousTicks &- sleepTicks()
    }

    /// The continuous clock's lead over the absolute clock, in ticks. The two are read one after the other, so the
    /// difference can be negative. It wraps rather than trapping, and the additions that use it wrap back to the right value.
    static func sleepTicks() -> UInt64 {
        mach_continuous_time() &- mach_absolute_time()
    }

    static func continuousMicroseconds(
        hostTicks: UInt64, sleepTicks: UInt64, timebase: mach_timebase_info_data_t
    ) -> UInt64 {
        let nanoseconds = (hostTicks &+ sleepTicks) * UInt64(timebase.numer) / UInt64(timebase.denom)
        return nanoseconds / 1_000
    }
}
