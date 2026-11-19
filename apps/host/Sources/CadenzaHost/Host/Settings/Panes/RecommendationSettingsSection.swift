import SwiftUI

/// Queue recommendations, planned from listening history. The choice is stored in the recommendation store, not in
/// the saved configuration, so it applies at once without a restart.
struct RecommendationSettingsSection: View {
    @Bindable var model: HostModel
    @State private var enabled = true
    @State private var mode = "auto"

    var body: some View {
        Section {
            Toggle(
                "Recommend songs for the queue",
                isOn: Binding(
                    get: { enabled },
                    set: { value in
                        do {
                            try model.service?.store.setCREEEnabled(value)
                            enabled = value
                        } catch {
                            model.showError("Recommendations could not be saved", error.localizedDescription)
                        }
                    })
            )
            Picker(
                "Mode",
                selection: Binding(
                    get: { mode },
                    set: { value in
                        do {
                            try model.service?.store.setRecommendationMode(value)
                            mode = value
                        } catch {
                            model.showError("Recommendation mode could not be saved", error.localizedDescription)
                        }
                    })
            ) {
                Text("Automatic").tag("auto")
                Text("Observe only").tag("shadow")
                Text("Plan the queue").tag("planning")
                Text("Paused").tag("paused")
            }
        } header: {
            Text("Recommendations")
        } footer: {
            Text(footerText)
        }
        .onAppear(perform: reload)
    }

    private var footerText: String {
        guard enabled else { return "Off. Learning data is kept, and no songs are added to the queue." }
        let phase = model.service.flatMap { try? $0.store.recommendationPhase } ?? "learning"
        let reason =
            model.service.flatMap { try? $0.store.recommendationPhaseReason } ?? "Waiting for a valid profile."
        switch mode {
        case "shadow":
            return "Observe only. Recommendations are scored and outcomes recorded, but Music is not changed."
        case "planning": return "Plan the queue. Cadenza Host may add one upcoming song under the queue rules."
        case "paused": return "Paused. The current profile and queue are kept."
        case "auto":
            let label = phase == "ready" ? "Ready to plan" : phase.capitalized
            return "Automatic · \(label). \(reason)"
        default: return "Recommendations are unavailable until the mode is repaired."
        }
    }

    private func reload() {
        guard let service = model.service else { return }
        enabled = (try? service.store.creeEnabled) ?? true
        mode = (try? service.store.recommendationMode) ?? "auto"
    }
}
