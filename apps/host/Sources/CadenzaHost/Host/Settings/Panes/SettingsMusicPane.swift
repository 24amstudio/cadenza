import SwiftUI

struct SettingsMusicPane: View {
    @Bindable var model: HostModel
    @State private var assignments: [String: String] = [:]
    @State private var discardMissing = false

    var body: some View {
        Form {
            Section {
                Button("Allow Accessibility") { model.service?.music.accessibility.requestPermission() }
                Button("Check Music Automation") {
                    Task { @MainActor in
                        do {
                            _ = try await model.service?.music.status()
                            model.notify("Music Automation is available.")
                        } catch { model.showError("Allow Music Automation", error.localizedDescription) }
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text(
                    "Open Music's Playing Next panel to verify the native queue. Open lyrics to fill Music's lyric cache."
                )
            }

            if let service = model.service {
                Section {
                    ForEach(service.queue.nativeRows, id: \.token) { row in
                        Picker(
                            row.title + " — " + row.artist,
                            selection: Binding(
                                get: { assignments[row.token] ?? "" },
                                set: { assignments[row.token] = $0.isEmpty ? nil : $0 })
                        ) {
                            Text("Cadenza Host").tag("")
                            ForEach(savedRequests(service), id: \.id) { entry in Text(entry.label).tag(entry.id) }
                        }
                    }
                    Toggle("Cancel saved requests not assigned to a native row", isOn: $discardMissing)
                    Button("Apply verified assignments") {
                        do {
                            try service.queue.reconcile(assignments, discardMissing: discardMissing)
                            model.notify("Native queue assignments saved.")
                        } catch { model.showError("Queue could not be reconciled", error.localizedDescription) }
                    }
                } header: {
                    Text("Reconcile native queue")
                } footer: {
                    Text("Use this after Music's queue changes outside Cadenza Host.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Music")
        .onAppear {
            assignments = model.service?.queue.nativeAssignments ?? [:]
        }
    }

    private struct SavedRequest: Identifiable {
        let id: String
        let label: String
    }

    private func savedRequests(_ service: HostService) -> [SavedRequest] {
        (try? service.store.pending().compactMap { row in
            guard let id = row["entry_id"]?.string, let title = row["title"]?.string else { return nil }
            let name = try service.store.remoteName(row["requested_by"]?.string)
            return SavedRequest(id: id, label: title + " · " + name)
        }) ?? []
    }
}
