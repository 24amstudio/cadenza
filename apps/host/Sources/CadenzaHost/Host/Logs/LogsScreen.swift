import SwiftUI

/// Live Host and Remote logs. The section listens to the logger only while it is on screen.
struct LogsScreen: View {
    @Bindable var model: HostModel
    @State private var logs = LogsModel()
    @State private var selection = Set<LogRow.ID>()
    @State private var showsDetail = false
    // Changes after each read of stored entries, so the table can jump to the newest row when a filter is applied.
    @State private var loadedToken = 0
    @State private var safeRecovery = CrashLoopGuard.safeRecoveryActive()

    var body: some View {
        VStack(spacing: 0) {
            if model.previousCrashRecord != nil {
                CrashReportBanner(export: exportDiagnostics) {
                    model.previousCrashRecord = nil
                }
                Divider()
            }
            if safeRecovery {
                SafeRecoveryBanner {
                    model.service?.resumeAutomaticMusicPolling()
                    safeRecovery = CrashLoopGuard.safeRecoveryActive()
                }
                Divider()
            }
            LogFilterBar(logs: logs)
            Divider()
            content
            Divider()
            LogStatusBar(
                shown: logs.rows.count, held: logs.buffer.heldCount, isPaused: logs.isPaused,
                totalStored: logs.totalStored, retentionDays: HostLogRetention.days)
        }
        .searchable(text: $logs.filter.search, placement: .toolbar, prompt: "Search logs")
        .toolbar { toolbar }
        .inspector(isPresented: $showsDetail) {
            LogDetailView(rows: selectedRows, copy: copy)
                .inspectorColumnWidth(min: 240, ideal: 300, max: 440)
        }
        .onAppear { logs.start(logger: model.service?.logger) }
        .onDisappear { logs.stop() }
        .onChange(of: model.service.map(ObjectIdentifier.init)) { logs.start(logger: model.service?.logger) }
        .onChange(of: logs.loadState) { if logs.loadState == .loaded { loadedToken += 1 } }
    }

    private var selectedRows: [LogRow] { logs.rows.filter { selection.contains($0.id) } }

    @ViewBuilder private var content: some View {
        if !logs.isWatching {
            ContentUnavailableView(
                "Host is not running", systemImage: "waveform.slash",
                description: Text("Logs appear here once Host has started."))
        } else if case .failed(let message) = logs.loadState {
            ContentUnavailableView {
                Label("Logs could not be read", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { logs.reload() }
            }
        } else if logs.loadState == .loading, logs.rows.isEmpty {
            ProgressView("Loading logs…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if logs.rows.isEmpty {
            empty
        } else {
            LogTable(
                rows: logs.rows, isPaused: logs.isPaused, loadedToken: loadedToken, selection: $selection, copy: copy)
        }
    }

    @ViewBuilder private var empty: some View {
        if logs.filter.isDefault {
            ContentUnavailableView(
                "No log entries yet", systemImage: "text.alignleft",
                description: Text("New entries appear here as Host and Remotes report them."))
        } else {
            ContentUnavailableView {
                Label("No matching entries", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Nothing in the stored logs matches these filters.")
            } actions: {
                Button("Reset Filters") { logs.resetFilter() }
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                logs.togglePause()
            } label: {
                Label(
                    logs.isPaused ? "Resume" : "Pause",
                    systemImage: logs.isPaused ? "play.fill" : "pause.fill")
            }
            .help(logs.isPaused ? "Show new entries again" : "Hold the view still while new entries keep counting")
            Button {
                logs.clearView()
                selection.removeAll()
                model.notify("View cleared. Stored logs are unchanged.")
            } label: {
                Label("Clear View", systemImage: "eraser")
            }
            .help("Clear what is on screen. Stored logs are kept.")
            .disabled(logs.rows.isEmpty)
            Menu {
                Button("Copy Selected Entries") { copy(selectedRows) }.disabled(selection.isEmpty)
                Button("Copy All Shown") { copy(logs.rows) }.disabled(logs.rows.isEmpty)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .help("Copy entries as plain text")
            Menu {
                Button("Export Shown as Text…") { export(.text) }
                Button("Export Shown as JSON…") { export(.json) }
                Divider()
                Button("Export Diagnostic Logs…") { exportDiagnostics() }
                    .disabled(model.service?.logger.mirror == nil)
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(logs.rows.isEmpty)
            .help("Save the entries on screen to a file")
            Toggle(isOn: $showsDetail) {
                Label("Details", systemImage: "sidebar.trailing")
            }
            .help("Show details of the selected entry")
        }
    }

    private func copy(_ rows: [LogRow]) {
        guard !rows.isEmpty else { return }
        LogExport.copy(rows)
        model.notify(rows.count == 1 ? "Copied 1 log entry." : "Copied \(rows.count) log entries.")
    }

    private func exportDiagnostics() {
        guard let mirror = model.service?.logger.mirror else { return }
        do {
            if let name = try LogExport.saveDiagnostics(mirror) { model.notify("Saved \(name).") }
        } catch {
            model.notify("Diagnostic logs could not be saved: \(error.localizedDescription)")
        }
    }

    private func export(_ format: LogExport.Format) {
        do {
            if let name = try LogExport.save(logs.rows, as: format) { model.notify("Saved \(name).") }
        } catch {
            model.showError("Logs could not be saved", error.localizedDescription)
        }
    }
}
