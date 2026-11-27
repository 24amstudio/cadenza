import Darwin
import XCTest

@testable import CadenzaHost

/// The Remote's playout times come from device times through the sleep offset. These tests pin the conversion, including
/// the case where the continuous clock reads behind the absolute clock, which must not trap.
final class RemoteAudioClockTests: XCTestCase {
    private func timebase(numer: UInt32, denom: UInt32) -> mach_timebase_info_data_t {
        var timebase = mach_timebase_info_data_t()
        timebase.numer = numer
        timebase.denom = denom
        return timebase
    }

    func testDeviceTimeConvertsToMicrosecondsOfTheContinuousClock() {
        // Apple silicon counts 24 MHz ticks of 125/3 nanoseconds, so one second is 24 000 000 ticks.
        let micros = RemoteAudioClock.continuousMicroseconds(
            hostTicks: 24_000_000, sleepTicks: 0, timebase: timebase(numer: 125, denom: 3))

        XCTAssertEqual(micros, 1_000_000)
    }

    func testAContinuousClockThatReadsBehindTheAbsoluteClockDoesNotTrap() {
        // A negative sleep offset in the wrapped form `sleepTicks()` returns: five ticks behind.
        let behind = UInt64(bitPattern: -5)
        let micros = RemoteAudioClock.continuousMicroseconds(
            hostTicks: 1_000_000, sleepTicks: behind, timebase: timebase(numer: 1, denom: 1))

        XCTAssertEqual(micros, 999)
    }

    func testTheLiveConversionMatchesTheContinuousClock() {
        let now = RemoteAudioClock.nowUs()
        let fromDevice = RemoteAudioClock.continuousUs(forHostTime: mach_absolute_time())

        XCTAssertLessThan(abs(Int64(fromDevice) - Int64(now)), 1_000_000)
    }
}
