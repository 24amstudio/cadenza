import Testing

@testable import CadenzaHost

struct MusicProcessTests {
    @Test func aFreshLookupWins() {
        #expect(MusicProcess.resolve(lookup: 200, lastKnown: 100, isRunning: { _ in true }) == 200)
    }

    @Test func aMissedLookupKeepsTheLastKnownProcessWhileItRuns() {
        #expect(MusicProcess.resolve(lookup: nil, lastKnown: 100, isRunning: { $0 == 100 }) == 100)
    }

    @Test func aMissedLookupReportsNotRunningOnceTheLastKnownProcessIsGone() {
        #expect(MusicProcess.resolve(lookup: nil, lastKnown: 100, isRunning: { _ in false }) == nil)
        #expect(MusicProcess.resolve(lookup: nil, lastKnown: nil, isRunning: { _ in true }) == nil)
    }
}
