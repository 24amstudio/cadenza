import AppKit
import SwiftUI
import Translation

struct HostSettings: View {
    @Bindable var model: HostModel
    @State private var translationSource = "ja"
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var preparingTranslation = false
    @State private var assignments: [String: String] = [:]
    @State private var discardMissing = false
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @State private var changelog: String?
    @State private var comparingChanges = false
    private let cacheLimits: [Int64] = [64, 128, 256, 512, 768, 1_024].map { Int64($0) * 1_048_576 }

    var body: some View {
        Form {
            Section("Cadenza Host") {
                Text(HostBuild.version + " · " + HostBuild.profile)
                Text(HostBuild.identity).textSelection(.enabled)
                Button("Changes in this build") { changelog = HostChangelog.bundled() }
                Button(comparingChanges ? "Comparing…" : "Compare published changes") {
                    comparingChanges = true
                    Task { @MainActor in
                        defer { comparingChanges = false }
                        do {
                            changelog = try await HostChangelog.compare(configuration: model.configuration.updates)
                        } catch { model.showError("Changes could not be compared", error.localizedDescription) }
                    }
                }.disabled(comparingChanges)
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
                Text("Open Cadenza Host from Spotlight to return to Settings when the icon is hidden.")
                Button("Run setup again") { model.showingSetup = true }
                Button("Quit Cadenza Host") {
                    model.service?.stop()
                    NSApplication.shared.terminate(nil)
                }
            }
            Section("Network") {
                TextField("Host name", text: $model.configuration.name)
                TextField("Port", value: $model.configuration.port, format: .number)
                TextField("Catalog storefront, for example id or us", text: $model.configuration.storefront)
                Picker("Address shown in pairing", selection: $model.configuration.advertisedAddress) {
                    Text("Automatic").tag("")
                    ForEach(LANAddresses.all(), id: \.self) { Text($0).tag($0) }
                }
                Button(model.saving ? "Saving…" : "Save settings", action: model.save).disabled(model.saving)
            }
            Section("Music permissions") {
                Button("Allow Accessibility") { model.service?.music.accessibility.requestPermission() }
                Button("Check Music Automation") {
                    Task { @MainActor in
                        do {
                            _ = try await model.service?.music.status()
                            model.notify("Music Automation is available.")
                        } catch { model.showError("Allow Music Automation", error.localizedDescription) }
                    }
                }
                Text(
                    "Open Music's Playing Next panel for native queue verification. Open lyrics to populate Music's lyric cache."
                )
            }
            Section("Lyrics providers") {
                Toggle("Use LRCLIB when Music has no lyrics", isOn: $model.configuration.lyricsProviderEnabled)
                Text(
                    "Cadenza Host sends the song title, artist, album, and duration over HTTPS. Results are cached on Host and shared with Remotes; Remote devices never contact the provider."
                )
            }
            Section("Local cache") {
                Picker("Maximum size", selection: $model.configuration.cacheLimitBytes) {
                    ForEach(cacheLimits, id: \.self) { value in
                        Text(ByteCountFormatter.string(fromByteCount: value, countStyle: .file)).tag(value)
                    }
                }
                if let stats = model.cacheStats {
                    Text(
                        "Using \(ByteCountFormatter.string(fromByteCount: stats.bytes, countStyle: .file)) across \(stats.entries) cached items."
                    )
                    ProgressView(value: min(stats.fractionUsed, 1))
                        .accessibilityLabel("Local cache usage")
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(
                    "The default is 256 MB. Lyrics and other Host-owned derived data are reused locally before an external lookup. The limit is enforced by removing the least recently used items."
                )
                Text("Save settings to apply a new limit.")
                HStack {
                    Button("Refresh") { model.refreshCacheStats() }
                    Button(model.clearingCache ? "Clearing…" : "Clear local cache", role: .destructive) {
                        model.clearCache()
                    }.disabled(model.clearingCache)
                }
            }
            Section("System logs") {
                Picker(
                    "Keep logs for",
                    selection: Binding(
                        get: { HostLogRetention.days }, set: { HostLogRetention.days = $0 })
                ) {
                    ForEach([7, 14, 30], id: \.self) { days in Text("\(days) days").tag(days) }
                }
                Text("Logs are stored separately from the media cache and never count toward its size limit.")
            }
            Section("English translation") {
                TextField("Source language code", text: $translationSource)
                Button(preparingTranslation ? "Preparing language pair…" : "Prepare English translation") {
                    preparingTranslation = true
                    translationConfiguration = TranslationSession.Configuration(
                        source: Locale.Language(identifier: translationSource),
                        target: Locale.Language(identifier: "en")
                    )
                }.disabled(preparingTranslation)
                Text("macOS asks before downloading a missing language model. Translation then stays in Cadenza Host.")
            }
            Section("Reconcile native queue") {
                if let service = model.service {
                    ForEach(service.queue.nativeRows, id: \.token) { row in
                        Picker(
                            row.title + " — " + row.artist,
                            selection: Binding(
                                get: { assignments[row.token] ?? "" },
                                set: { assignments[row.token] = $0.isEmpty ? nil : $0 }
                            )
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
                }
            }
            Section("GitHub Releases") {
                TextField("Repository, owner/name", text: $model.configuration.updates.repository)
                TextField("Public P-256 key, SPKI base64", text: $model.configuration.updates.publicKeySpkiBase64)
                Toggle("Check and install updates automatically", isOn: $model.configuration.automaticUpdates).disabled(
                    !HostBuild.updatesEnabled)
                HStack {
                    Button(model.updateBusy ? "Checking…" : "Check for updates") { model.checkUpdates() }.disabled(
                        model.updateBusy || !HostBuild.updatesEnabled)
                    if let version = model.stagedVersion { Button("Install \(version)") { model.installUpdate() } }
                }
                if model.updateBusy { ProgressView(value: model.updateProgress) }
                Text(
                    "Save settings to apply the repository and verification key. Updates preserve the database and Keychain identity."
                )
                if !HostBuild.updatesEnabled { Text("Automatic updates are disabled in this build.") }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: Binding(get: { changelog != nil }, set: { if !$0 { changelog = nil } })) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Changelog").font(.title.bold())
                ScrollView {
                    Text(changelog ?? "").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Close") { changelog = nil }.keyboardShortcut(.cancelAction)
            }.padding(24).frame(width: 560, height: 420)
        }
        .onAppear { assignments = model.service?.queue.nativeAssignments ?? [:] }
        .translationTask(translationConfiguration) { @concurrent session in
            // The framework runs prepareTranslation off the main actor, so the session stays off it too.
            do {
                try await session.prepareTranslation()
                await MainActor.run {
                    preparingTranslation = false
                    model.notify("English translation is ready.")
                }
            } catch {
                await MainActor.run {
                    preparingTranslation = false
                    model.showError("Could not prepare translation", error.localizedDescription)
                }
            }
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
