import Foundation
import Testing

@testable import CadenzaHost

@MainActor
private final class FakeDesktop: FrontApplications {
    static let music = FrontApplication(processId: 10, bundleId: ActivationFallback.musicBundleId)
    static let editor = FrontApplication(processId: 20, bundleId: "com.example.editor")
    static let browser = FrontApplication(processId: 30, bundleId: "com.example.browser")

    var frontmost: FrontApplication?
    var musicComesForward = true
    var activations: [FrontApplication] = []
    var time: Int64 = 1_000

    init(frontmost: FrontApplication? = FakeDesktop.editor) { self.frontmost = frontmost }

    func running(bundleId: String) -> FrontApplication? {
        bundleId == ActivationFallback.musicBundleId ? Self.music : nil
    }

    func activate(_ application: FrontApplication) {
        activations.append(application)
        if application != Self.music || musicComesForward { frontmost = application }
    }

    func fallback() -> ActivationFallback {
        ActivationFallback(
            applications: self, now: { [unowned self] in time },
            sleep: { [unowned self] in time += $0 })
    }
}

private func unavailable(_ message: String = "no") -> CadenzaError {
    CadenzaError.failure("native_queue_unavailable", message)
}

@MainActor
struct ActivationFallbackTests {
    private func step(
        _ name: String, _ tier: ActivationFallback.Tier, log: Log, result: Result<String, CadenzaError>
    ) -> ActivationFallback.Step<String> {
        .init(name: name, tier: tier) { _ in
            log.names.append(name)
            return try result.get()
        }
    }

    @MainActor final class Log { var names: [String] = [] }

    @Test func neverActivatesWhenAQuietStepSucceeds() async throws {
        let desktop = FakeDesktop()
        let log = Log()

        let value = try await desktop.fallback().run(
            deadline: 5_000,
            steps: [
                step("ax", .quiet, log: log, result: .success("done")),
                step("front", .activating, log: log, result: .success("forced")),
            ])

        #expect(value == "done")
        #expect(log.names == ["ax"])
        #expect(desktop.activations.isEmpty)
        #expect(desktop.frontmost == FakeDesktop.editor)
    }

    @Test func triesQuietStepsInOrderThenActivatesAndHandsFocusBack() async throws {
        let desktop = FakeDesktop()
        let log = Log()
        var frontmostDuringActivatingStep: FrontApplication?

        let value = try await desktop.fallback().run(
            deadline: 5_000,
            steps: [
                step("ax", .quiet, log: log, result: .failure(unavailable())),
                step("pid", .quiet, log: log, result: .failure(unavailable())),
                .init(name: "front", tier: .activating) { _ in
                    log.names.append("front")
                    frontmostDuringActivatingStep = desktop.frontmost
                    return "forced"
                },
            ])

        #expect(value == "forced")
        #expect(log.names == ["ax", "pid", "front"])
        #expect(frontmostDuringActivatingStep == FakeDesktop.music)
        #expect(desktop.activations == [FakeDesktop.music, FakeDesktop.editor])
        #expect(desktop.frontmost == FakeDesktop.editor)
    }

    @Test func handsFocusBackWhenTheActivatingStepFails() async {
        let desktop = FakeDesktop()
        let log = Log()

        await #expect(throws: CadenzaError.self) {
            try await desktop.fallback().run(
                deadline: 5_000,
                steps: [
                    step("ax", .quiet, log: log, result: .failure(unavailable("ax refused"))),
                    step("front", .activating, log: log, result: .failure(unavailable("click missed"))),
                ])
        }

        #expect(desktop.frontmost == FakeDesktop.editor)
        #expect(desktop.activations == [FakeDesktop.music, FakeDesktop.editor])
    }

    @Test func reportsEveryFailureWithTheLastCode() async {
        let desktop = FakeDesktop()
        let log = Log()

        do {
            _ = try await desktop.fallback().run(
                deadline: 5_000,
                steps: [
                    step("ax", .quiet, log: log, result: .failure(unavailable("ax refused"))),
                    step(
                        "front", .activating, log: log,
                        result: .failure(.failure("music_window_unavailable", "no window"))),
                ])
            Issue.record("Expected the run to fail")
        } catch let error as CadenzaError {
            #expect(error.code == "music_window_unavailable")
            #expect(error.localizedDescription.contains("ax refused"))
            #expect(error.localizedDescription.contains("no window"))
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func anUnrecoverableErrorStopsBeforeActivation() async {
        let desktop = FakeDesktop()
        let log = Log()

        await #expect(throws: CadenzaError.self) {
            try await desktop.fallback().run(
                deadline: 5_000,
                steps: [
                    step("ax", .quiet, log: log, result: .failure(.failure("forbidden", "not yours"))),
                    step("front", .activating, log: log, result: .success("forced")),
                ])
        }

        #expect(log.names == ["ax"])
        #expect(desktop.activations.isEmpty)
    }

    @Test func leavesFocusAloneWhenTheUserMovedOnDuringTheStep() async throws {
        let desktop = FakeDesktop()

        _ = try await desktop.fallback().run(
            deadline: 5_000,
            steps: [
                ActivationFallback.Step<String>(name: "front", tier: .activating) { _ in
                    desktop.frontmost = FakeDesktop.browser
                    return "done"
                }
            ])

        #expect(desktop.activations == [FakeDesktop.music])
        #expect(desktop.frontmost == FakeDesktop.browser)
    }

    @Test func doesNotActivateOrRestoreWhenMusicIsAlreadyInFront() async throws {
        let desktop = FakeDesktop(frontmost: FakeDesktop.music)

        let value = try await desktop.fallback().run(
            deadline: 5_000,
            steps: [ActivationFallback.Step<String>(name: "front", tier: .activating) { _ in "done" }])

        #expect(value == "done")
        #expect(desktop.activations.isEmpty)
    }

    @Test func failsWithoutRunningTheActivatingStepWhenMusicNeverComesForward() async {
        let desktop = FakeDesktop()
        desktop.musicComesForward = false
        let log = Log()

        await #expect(throws: CadenzaError.self) {
            try await desktop.fallback().run(
                deadline: 10_000, steps: [step("front", .activating, log: log, result: .success("forced"))])
        }

        #expect(log.names.isEmpty)
        #expect(desktop.frontmost == FakeDesktop.editor)
    }

    @Test func anAttemptThatRunsOutOfItsShareEscalatesButAnExpiredCommandDoesNot() async throws {
        let desktop = FakeDesktop()
        let log = Log()
        let value = try await desktop.fallback().run(
            deadline: 5_000,
            steps: [
                step("ax", .quiet, log: log, result: .failure(.failure("expired", "slow"))),
                step("pid", .quiet, log: log, result: .success("done")),
            ])
        #expect(value == "done")

        desktop.time = 6_000
        do {
            _ = try await desktop.fallback().run(
                deadline: 5_000,
                steps: [
                    step("ax", .quiet, log: log, result: .failure(.failure("expired", "late"))),
                    step("front", .activating, log: log, result: .success("forced")),
                ])
            Issue.record("Expected the expired command to fail")
        } catch let error as CadenzaError {
            #expect(error.code == "expired")
        }
        #expect(desktop.activations.isEmpty)
    }
}
