import SwiftUI

struct SettingsRecommendationsPane: View {
    @Bindable var model: HostModel
    @State private var creeEnabled = true
    @State private var creeMode = "auto"

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Enable CREE",
                    isOn: Binding(
                        get: { creeEnabled },
                        set: { value in
                            do {
                                try model.service?.store.setCREEEnabled(value)
                                creeEnabled = value
                            } catch {
                                model.showError("CREE setting could not be saved", error.localizedDescription)
                            }
                        })
                )
                Picker(
                    "Mode",
                    selection: Binding(
                        get: { creeMode },
                        set: { value in
                            do {
                                try model.service?.store.setRecommendationMode(value)
                                creeMode = value
                            } catch {
                                model.showError("CREE mode could not be saved", error.localizedDescription)
                            }
                        })
                ) {
                    Text("Auto").tag("auto")
                    Text("Shadow").tag("shadow")
                    Text("Planning").tag("planning")
                    Text("Paused").tag("paused")
                }
            } footer: {
                Text(creeEnabled ? phaseDescription : "Disabled. Learning data is kept, and no queue planning runs.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Recommendations")
        .onAppear(perform: reloadCREE)
    }

    private var phaseDescription: String {
        let phase = model.service.flatMap { try? $0.store.recommendationPhase } ?? "learning"
        let reason =
            model.service.flatMap { try? $0.store.recommendationPhaseReason } ?? "Waiting for a valid profile."
        if creeMode == "auto" {
            let label = phase == "ready" ? "Ready to plan" : phase.capitalized
            return "Auto · \(label). \(reason)"
        }
        switch creeMode {
        case "auto": return "Learning. Auto mode observes first and plans only after Host readiness gates pass."
        case "shadow": return "Shadow. CREE scores candidates and observes outcomes without changing Music."
        case "planning": return "Planning. CREE may submit one next occurrence under Host queue policy."
        case "paused": return "Paused. The current profile and queue are preserved."
        default: return "CREE is unavailable until its mode is repaired."
        }
    }

    private func reloadCREE() {
        guard let service = model.service else { return }
        creeEnabled = (try? service.store.creeEnabled) ?? true
        creeMode = (try? service.store.recommendationMode) ?? "auto"
    }
}
