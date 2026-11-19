import SwiftUI

/// Offers one restart for the settings on a pane that the running Host has not picked up yet.
struct RestartHostSection: View {
    let model: HostModel
    let settings: Set<RestartSetting>

    var body: some View {
        if model.restartPending(settings) {
            Section {
                Button(model.saving ? "Restarting Host…" : "Restart Host to apply", action: model.restartToApply)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.saving)
            } footer: {
                Text("Host restarts for a moment, and paired Remotes reconnect on their own.")
            }
        }
    }
}
