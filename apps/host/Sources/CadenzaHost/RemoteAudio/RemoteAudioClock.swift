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
        let sleepTicks = mach_continuous_time() - mach_absolute_time()
        let nanoseconds = (hostTime + sleepTicks) * UInt64(timebase.numer) / UInt64(timebase.denom)
        return nanoseconds / 1_000
    }

    /// The mach absolute time at which a playout instant on this clock occurs. `AVAudioTime` schedules in that domain,
    /// which differs from the continuous clock only by the time the Mac has slept.
    static func machAbsoluteTime(forPlayoutUs playoutUs: UInt64) -> UInt64 {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let continuousTicks = playoutUs * 1_000 * UInt64(timebase.denom) / UInt64(timebase.numer)
        let sleepTicks = mach_continuous_time() - mach_absolute_time()
        return continuousTicks - sleepTicks
    }
}
