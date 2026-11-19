import SwiftUI

struct HostWindow: View {
    @Bindable var model: HostModel

    var body: some View {
        Group {
            if !model.onboardingComplete || model.showingSetup {
                HostOnboarding(model: model)
            } else {
                HostWorkspace(model: model)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(16)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .alert(item: $model.prompt) { prompt in
            Alert(title: Text(prompt.title), message: Text(prompt.message), dismissButton: .default(Text("OK")))
        }
        .sheet(
            item: Binding(
                get: { model.invitation.map(PairingSheetItem.init) },
                set: { if $0 == nil { model.invitation = nil } }
            )
        ) { item in
            PairingSheet(invitation: item.invitation)
        }
    }
}
