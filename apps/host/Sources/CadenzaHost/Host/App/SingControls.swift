import SwiftUI

struct SingControls: View {
    @Bindable var model: HostModel
    @State private var draftVocalPercent: Double?

    var body: some View {
        let sing = model.snapshot?.sing
        let active = sing?.status == "active"
        let vocalPercent = sing?.vocalPercent ?? 0
        VStack(spacing: 10) {
            Button {
                model.singControl(active ? "sing.disable" : "sing.enable")
            } label: {
                Label(active ? "Turn Off Sing" : "Start Sing", systemImage: "mic.fill")
            }
            .buttonStyle(.bordered)
            .disabled(sing?.status == "preparing" || model.controlling)
            if active {
                Slider(
                    value: level(vocalPercent), in: 0...100, step: 5,
                    label: { Text("Vocal level") },
                    minimumValueLabel: { Text("0") },
                    maximumValueLabel: { Text("100") },
                    onEditingChanged: commit
                )
                .frame(maxWidth: 360)
                .onChange(of: vocalPercent) { _, _ in draftVocalPercent = nil }
            }
            if let status = statusText(sing) {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func level(_ vocalPercent: Int) -> Binding<Double> {
        Binding(
            get: { draftVocalPercent ?? Double(vocalPercent) },
            set: { draftVocalPercent = $0 })
    }

    private func commit(_ editing: Bool) {
        guard !editing, let draftVocalPercent else { return }
        model.singControl("sing.mix", vocalPercent: Int(draftVocalPercent))
    }

    private func statusText(_ sing: SingSession?) -> String? {
        switch sing?.status ?? "" {
        case "preparing": "Preparing Sing…"
        case "failed": sing?.issue ?? "Sing could not start."
        default: nil
        }
    }
}
