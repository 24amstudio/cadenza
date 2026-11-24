import Foundation
import Testing

@testable import CadenzaHost

struct HostBudgetPolicyTests {
    @Test func thermalPressureSetsTheTierAndLowPowerModeOnlyLiftsUnrestrictedWork() {
        #expect(HostBudgetPolicy.budget(for: HostPowerState(thermal: .nominal, lowPowerMode: false)) == .unrestricted)
        #expect(HostBudgetPolicy.budget(for: HostPowerState(thermal: .nominal, lowPowerMode: true)) == .balanced)
        #expect(HostBudgetPolicy.budget(for: HostPowerState(thermal: .fair, lowPowerMode: false)) == .balanced)
        #expect(HostBudgetPolicy.budget(for: HostPowerState(thermal: .serious, lowPowerMode: true)) == .constrained)
        #expect(HostBudgetPolicy.budget(for: HostPowerState(thermal: .critical, lowPowerMode: false)) == .survival)
    }

    @Test func singInferenceIsPausedOnlyFromTheConstrainedTier() {
        #expect(HostOperatingBudget.balanced.allowsSingInference)
        #expect(!HostOperatingBudget.constrained.allowsSingInference)
        #expect(!HostOperatingBudget.survival.allowsSingInference)
        #expect(HostOperatingBudget.survival > .constrained)
    }

    @Test func theBudgetCrossesTheWireByItsName() throws {
        let encoded = try JSONEncoder().encode(HostOperatingBudget.constrained)

        #expect(String(decoding: encoded, as: UTF8.self) == "\"constrained\"")
    }

    @Test func processInfoThermalStatesMapOneToOne() {
        let states: [ProcessInfo.ThermalState] = [.nominal, .fair, .serious, .critical]
        let mapped = states.map { HostThermalLevel($0) }

        #expect(mapped == [.nominal, .fair, .serious, .critical])
    }
}
