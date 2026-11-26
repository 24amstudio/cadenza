import Foundation
import Testing

@testable import CadenzaHost

@MainActor
struct SleepAssertionTests {
    @Test func aReleaseWaitsForTheIdleTimeoutAndNewActivityCancelsIt() async throws {
        let sleep = SleepAssertion(idleTimeout: .milliseconds(300))
        defer { sleep.releaseNow() }

        sleep.update(active: true)
        sleep.update(active: false)
        #expect(sleep.isHolding)

        sleep.update(active: true)
        try await Task.sleep(for: .milliseconds(500))
        #expect(sleep.isHolding)

        sleep.update(active: false)
        try await Task.sleep(for: .milliseconds(500))
        #expect(!sleep.isHolding)
    }

    @Test func theHeldAssertionIsListedByThePowerManager() throws {
        let sleep = SleepAssertion(idleTimeout: .seconds(60))
        defer { sleep.releaseNow() }

        sleep.update(active: true)
        #expect(sleep.isHolding)
        #expect(try pmsetAssertions().contains(SleepAssertion.reason))
    }

    private func pmsetAssertions() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "assertions"]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
