import AppKit
import ApplicationServices
import MusicKit
import SwiftUI

struct HostOnboarding: View {
    @Bindable var model: HostModel
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var step = 0
    @State private var busy = false
    @State private var manualStorefront = false
    @State private var automationVerified = false
    @State private var accessibilityVerified = false
    @State private var detectedStorefront = false
    @State private var detectionAttempt = UUID()
    @State private var detectionTask: Task<Void, Never>?
    @State private var detectionTimeout: Task<Void, Never>?

    var body: some View {
        NavigationSplitView {
            List {
                Section("Setup") {
                    ForEach(Array(["Welcome", "Apple Music", "Permissions", "Pair Remote"].enumerated()), id: \.offset) { index, label in
                        Label(label, systemImage: index == step ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(index == step ? .primary : .secondary)
                            .contentShape(Rectangle())
                            .onTapGesture { if index <= step && !busy { step = index } }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Cadenza Host")
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: step == 3 ? "qrcode" : "music.note.list")
                        .font(.title2.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.title.bold())
                        Text("Step \(step + 1) of 4").foregroundStyle(.secondary)
                    }
                    Spacer()
                    ProgressView(value: Double(step + 1), total: 4).frame(width: 120)
                }
                .padding(.horizontal, 28).padding(.vertical, 22)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) { stepContent }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(28)
                }
                Divider()
                HStack {
                    if step > 0 { Button("Back") { step -= 1 }.disabled(busy) }
                    Spacer()
                    if step < 3 { Text("You can change these settings later.").foregroundStyle(.secondary) }
                }
                .padding(.horizontal, 28).padding(.vertical, 16)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .tint(.accentColor)
        .onReceive(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
        ) { _ in
            accessibilityVerified = AXIsProcessTrusted()
        }
        .onDisappear {
            detectionTask?.cancel()
            detectionTimeout?.cancel()
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            Text(
                "Control Music from your Android devices. Audio stays on this Mac, while pairing and controls stay "
                    + "on your local network."
            )
            .font(.title3)
            Button("Get started") { step = 1 }.keyboardShortcut(.defaultAction)
        case 1:
            Text(
                "Cadenza uses your Apple Music storefront for catalog search. Detect it automatically or choose "
                    + "the region linked to your subscription."
            )
            Button(busy ? "Detecting storefront…" : "Detect Apple Music storefront") { detectStorefront() }
                .disabled(busy)
            if manualStorefront {
                Picker("Apple Music storefront", selection: $model.configuration.storefront) {
                    ForEach(
                        Locale.Region.isoRegions
                            .map(\.identifier)
                            .filter { $0.count == 2 }
                            .map { $0.lowercased() }
                            .sorted(),
                        id: \.self
                    ) { code in
                        Text(
                            Locale.current.localizedString(forRegionCode: code.uppercased()) ?? code.uppercased()
                        )
                        .tag(code)
                    }
                }
                .frame(maxWidth: 320)
            } else if detectedStorefront {
                Label(
                    "Storefront: " + model.configuration.storefront.uppercased(),
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
            }
            if manualStorefront || detectedStorefront {
                Button(busy ? "Saving…" : "Continue") { saveStorefront() }.disabled(busy)
            }
        case 2:
            Text(
                "Cadenza needs Automation to control Music and Accessibility to verify its Playing Next queue. "
                    + "macOS will ask for each permission."
            )
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Button(busy ? "Checking Music…" : "Allow and check Music Automation") { checkAutomation() }
                        .disabled(busy)
                    Label(
                        automationVerified ? "Music Automation verified" : "Music Automation needs approval",
                        systemImage: automationVerified ? "checkmark.circle.fill" : "circle"
                    )
                }
            } label: {
                Label("Music control", systemImage: "music.note")
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Button("Allow Accessibility") {
                        (model.service?.music ?? MusicBridge()).accessibility.requestPermission()
                    }
                    Button("Check Accessibility") { accessibilityVerified = AXIsProcessTrusted() }
                    Label(
                        accessibilityVerified
                            ? "Accessibility verified"
                            : "Approve Cadenza Host in Privacy & Security → Accessibility",
                        systemImage: accessibilityVerified ? "checkmark.circle.fill" : "circle"
                    )
                }
            } label: {
                Label("Queue verification", systemImage: "list.bullet.rectangle")
            }
            Text(
                "Local Network access is requested when Host starts listening. If macOS blocks it, allow Cadenza Host "
                    + "in Privacy & Security → Local Network."
            )
            .foregroundStyle(.secondary)
            Button("Continue to pairing") {
                busy = true
                Task { @MainActor in
                    defer { busy = false }
                    await model.start()
                    if model.running {
                        model.service?.startObservation()
                        step = 3
                    }
                }
            }.disabled(!automationVerified || !accessibilityVerified || busy)
        default:
            Text("Open Cadenza Remote, scan a pairing QR, and keep it connected until the Host confirms the link.")
            Button(model.running ? "Pair a Remote" : "Retry Host connection") {
                if model.running {
                    model.pair()
                } else {
                    Task { await model.start() }
                }
            }
            .disabled(model.starting)
            ForEach(model.connectedRemotes) { remote in
                Label(remote.name + " connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Button("Finish setup") {
                if model.finishOnboarding() { dismissWindow(id: "host") }
            }
            .disabled(model.connectedRemotes.isEmpty || !model.running)
        }
    }

    private var title: String {
        ["Welcome to Cadenza Host", "Apple Music storefront", "Allow Music control", "Pair your Remote"][step]
    }

    private func detectStorefront() {
        guard !busy else { return }
        busy = true
        let attempt = UUID()
        detectionAttempt = attempt
        detectionTask = Task { @MainActor in
            defer {
                if detectionAttempt == attempt {
                    busy = false
                    detectionTimeout?.cancel()
                }
            }
            let status =
                MusicAuthorization.currentStatus == .notDetermined
                ? await MusicAuthorization.request()
                : MusicAuthorization.currentStatus
            guard !Task.isCancelled, detectionAttempt == attempt else { return }
            guard status == .authorized else {
                manualStorefront = true
                return
            }
            do {
                let code = try await MusicDataRequest.currentCountryCode.lowercased()
                guard !Task.isCancelled, detectionAttempt == attempt else { return }
                guard code.range(of: "^[a-z]{2}$", options: .regularExpression) != nil else {
                    manualStorefront = true
                    return
                }
                model.configuration.storefront = code
                detectedStorefront = true
                manualStorefront = false
            } catch {
                if detectionAttempt == attempt { manualStorefront = true }
            }
        }
        detectionTimeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, detectionAttempt == attempt, busy else { return }
            detectionAttempt = UUID()
            detectionTask?.cancel()
            busy = false
            manualStorefront = true
            model.notify("Storefront detection timed out. Choose your Apple Music region to continue.")
        }
    }

    private func saveStorefront() {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                try model.configuration.save()
                if let service = model.service { try await service.save(model.configuration) }
                step = 2
            } catch { model.showError("Could not save storefront", error.localizedDescription) }
        }
    }

    private func checkAutomation() {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                _ = try await (model.service?.music ?? MusicBridge()).status()
                automationVerified = true
            } catch {
                automationVerified = false
                model.showError(
                    "Allow Music Automation",
                    error.localizedDescription + " Check Privacy & Security → Automation, then retry."
                )
            }
        }
    }
}
