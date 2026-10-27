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
        VStack(alignment: .leading, spacing: 22) {
            Text(title).font(.largeTitle.bold())
            switch step {
            case 0:
                Text(
                    "Control Music on this Mac from your Android devices. Audio stays on the Mac; pairing and controls stay on your local network."
                )
                Button("Get started") { step = 1 }.keyboardShortcut(.defaultAction)
            case 1:
                Text(
                    "Apple Music access lets Cadenza try the storefront of your signed-in music account. If this no-fee build cannot read it, you can choose it yourself."
                )
                Button(busy ? "Detecting storefront…" : "Detect Apple Music storefront") { detectStorefront() }
                    .disabled(busy)
                if manualStorefront {
                    Text(
                        "Automatic detection is unavailable. Choose the country or region of your Apple Music subscription."
                    )
                    Picker("Apple Music storefront", selection: $model.configuration.storefront) {
                        ForEach(
                            Locale.Region.isoRegions.map(\.identifier).filter { $0.count == 2 }.map { $0.lowercased() }
                                .sorted(), id: \.self
                        ) { code in
                            Text(Locale.current.localizedString(forRegionCode: code.uppercased()) ?? code.uppercased())
                                .tag(code)
                        }
                    }
                } else if detectedStorefront {
                    Text("Apple Music storefront: " + model.configuration.storefront.uppercased())
                }
                if manualStorefront || detectedStorefront {
                    Button(busy ? "Saving…" : "Continue") { saveStorefront() }.disabled(busy)
                }
            case 2:
                Text(
                    "Automation reads and controls Music. Accessibility verifies and edits its Playing Next queue. macOS asks you to approve access; Cadenza cannot grant it for you."
                )
                Button(busy ? "Checking Music…" : "Allow and check Music Automation") { checkAutomation() }.disabled(
                    busy)
                Label(
                    automationVerified ? "Music Automation verified" : "Music Automation needs approval",
                    systemImage: automationVerified ? "checkmark.circle" : "circle")
                Button("Allow Accessibility") {
                    (model.service?.music ?? MusicBridge()).accessibility.requestPermission()
                }
                Button("Check Accessibility") { accessibilityVerified = AXIsProcessTrusted() }
                Label(
                    accessibilityVerified
                        ? "Accessibility verified" : "Approve Cadenza Host in Privacy & Security → Accessibility",
                    systemImage: accessibilityVerified ? "checkmark.circle" : "circle")
                Text(
                    "Local network access is requested when Host starts listening. If it is denied, allow Cadenza Host in Privacy & Security → Local Network, then retry."
                )
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
                Text(
                    "Open Cadenza Remote, scan a pairing QR, and keep the tablet connected. A verified connection appears below."
                )
                Button(model.running ? "Pair a Remote" : "Retry Host connection") {
                    if model.running { model.pair() } else { Task { await model.start() } }
                }.disabled(model.starting)
                ForEach(model.connectedRemotes) { remote in
                    Label(remote.name + " connected", systemImage: "checkmark.circle")
                }
                Button("Finish setup") {
                    if model.finishOnboarding() { dismissWindow(id: "host") }
                }.disabled(model.connectedRemotes.isEmpty || !model.running)
            }
            Spacer(minLength: 0)
            HStack {
                if step > 0 { Button("Back") { step -= 1 }.disabled(busy) }
                Spacer()
                Text("Step \(step + 1) of 4").foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(minWidth: 560, minHeight: 480)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification))
        { _ in
            accessibilityVerified = AXIsProcessTrusted()
        }
        .onDisappear {
            detectionTask?.cancel()
            detectionTimeout?.cancel()
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
                ? await MusicAuthorization.request() : MusicAuthorization.currentStatus
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
            } catch { if detectionAttempt == attempt { manualStorefront = true } }
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
                    error.localizedDescription + " Check Privacy & Security → Automation, then retry.")
            }
        }
    }
}
