import AppKit
import SwiftUI

struct SettingsMusicPane: View {
    @Bindable var model: HostModel
    @State private var assignments: [String: String] = [:]
    @State private var discardMissing = false
    @State private var accessibilityGranted = false
    @State private var mediaUserToken = ""
    @State private var hasStoredMediaToken = false

    private var automation: PermissionState { model.service?.music.automation.state ?? .notChecked }

    var body: some View {
        Form {
            RestartHostSection(model: model, settings: [.storefront])
            Section {
                PermissionStatusRow(
                    title: "Automation",
                    explanation: "Lets Cadenza Host play, pause, and skip in Music.",
                    state: automation,
                    actionTitle: automation == .needed ? "Open System Settings" : "Check Automation",
                    actionDisabled: model.service == nil || automation == .checking,
                    action: {
                        if automation == .needed {
                            openAutomationSettings()
                        } else {
                            checkAutomation()
                        }
                    })
                PermissionStatusRow(
                    title: "Accessibility",
                    explanation:
                        "Lets Cadenza Host read Music's Playing Next list. If no prompt appears, turn it on in System Settings.",
                    state: accessibilityGranted ? .granted : .needed,
                    actionTitle: accessibilityGranted ? nil : "Allow Accessibility",
                    actionDisabled: model.service == nil,
                    action: { model.service?.music.accessibility.requestPermission() })
            } header: {
                Text("Permissions")
            } footer: {
                Text("macOS asks for these permissions. Cadenza Host can't turn them on for you.")
            }

            if let service = model.service {
                Section {
                    Button("Rebuild Queue From Music") { rebuildQueue(service) }
                    DisclosureGroup("Advanced") {
                        Toggle("Remove saved requests that no longer match Music", isOn: $discardMissing)
                        ForEach(service.queue.nativeRows, id: \.token) { row in
                            Picker(
                                row.title + " — " + row.artist,
                                selection: Binding(
                                    get: { assignments[row.token] ?? "" },
                                    set: { assignments[row.token] = $0.isEmpty ? nil : $0 })
                            ) {
                                Text("No saved request").tag("")
                                ForEach(savedRequests(service), id: \.id) { entry in
                                    Text(entry.label).tag(entry.id)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Queue")
                } footer: {
                    Text(
                        "Rebuild matches saved Cadenza requests to Music's current queue after Music changes outside Cadenza Host."
                    )
                }
            }

            RecommendationSettingsSection(model: model)

            SingModelSection(manager: model.singModel) { title, message in model.showError(title, message) }

            Section {
                ValidatedSettingField(
                    title: "Storefront",
                    value: model.configuration.storefront,
                    format: { $0 },
                    parse: SettingValue.storefront,
                    invalidMessage: "Use a two-letter country code, such as us.",
                    commit: { code in
                        model.configuration.storefront = code
                        model.persistConfiguration()
                    })
                if let service = model.service {
                    SecureField(
                        hasStoredMediaToken ? "Apple Music web token (saved)" : "Apple Music web token (optional)",
                        text: $mediaUserToken)
                    HStack {
                        Button("Save Web Token") { saveMediaUserToken(service) }
                            .disabled(mediaUserToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if hasStoredMediaToken {
                            Button("Clear Web Token", role: .destructive) { clearMediaUserToken(service) }
                        }
                    }
                }
            } header: {
                Text("Apple Music")
            } footer: {
                Text(
                    "The two-letter country code used to search Apple Music, such as us or id. "
                        + "An optional media-user-token enables AirPlay WebVTT karaoke and Widevine Cast video streams."
                )
            }
        }
        .formStyle(.grouped)
        .onAppear {
            assignments = model.service?.queue.nativeAssignments ?? [:]
            refreshAccessibility()
            refreshMediaUserTokenStatus()
            if let checker = model.service?.music.automation {
                Task { @MainActor in await checker.refresh(promptUser: false) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibility()
        }
    }

    private struct SavedRequest: Identifiable {
        let id: String
        let label: String
    }

    private func refreshAccessibility() {
        accessibilityGranted = model.service?.music.accessibility.permitted ?? false
    }

    private func refreshMediaUserTokenStatus() {
        guard let credentials = model.service?.store.credentials,
            let data = try? credentials.read(AppleWebPlayback.tokenAccount)
        else {
            hasStoredMediaToken = false
            return
        }
        hasStoredMediaToken = !data.isEmpty
    }

    private func saveMediaUserToken(_ service: HostService) {
        let trimmed = mediaUserToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try service.store.credentials.write(AppleWebPlayback.tokenAccount, Data(trimmed.utf8))
            mediaUserToken = ""
            hasStoredMediaToken = true
            model.notify("Apple Music web token saved.")
        } catch {
            model.showError("Could not save token", error.localizedDescription)
        }
    }

    private func clearMediaUserToken(_ service: HostService) {
        do {
            try service.store.credentials.delete(AppleWebPlayback.tokenAccount)
            mediaUserToken = ""
            hasStoredMediaToken = false
            model.notify("Apple Music web token cleared.")
        } catch {
            model.showError("Could not clear token", error.localizedDescription)
        }
    }

    // Only this explicit action may show macOS's Automation prompt. Launch and focus refreshes stay passive.
    private func checkAutomation() {
        guard let checker = model.service?.music.automation else { return }
        Task { @MainActor in
            switch await checker.refresh(promptUser: true) {
            case .granted:
                model.notify("Music Automation is available.")
            case .needed:
                model.showError(
                    "Allow Music Automation",
                    "Cadenza Host can't control Music. Turn on Music in System Settings → Privacy & Security → Automation, then check again."
                )
            case .notChecked, .checking:
                break
            }
        }
    }

    private func openAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func rebuildQueue(_ service: HostService) {
        do {
            try service.queue.reconcile(assignments, discardMissing: discardMissing)
            model.notify("Queue rebuilt from Music.")
        } catch {
            model.showError("Queue could not be rebuilt", error.localizedDescription)
        }
    }

    private func savedRequests(_ service: HostService) -> [SavedRequest] {
        (try? service.store.pending().compactMap { row in
            guard let id = row["entry_id"]?.string, let title = row["title"]?.string else { return nil }
            let name = try service.store.remoteName(row["requested_by"]?.string)
            return SavedRequest(id: id, label: title + " · " + name)
        }) ?? []
    }
}
