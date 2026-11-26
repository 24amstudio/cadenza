import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

/// The Cadenza TV settings: the `/tv` address, the TVs waiting for a PIN, and the TVs already approved. A TV is approved
/// here or from a paired Remote, and forgetting one revokes its token.
struct StageSettingsSection: View {
    @Bindable var model: HostModel
    @AppStorage("castTransmitChannelFormat") private var transmitFormat = CastTransmitChannelFormat.transcodeAuto
    @AppStorage(HostService.webLoaderAppIdKey) private var webLoaderAppId = ""
    @State private var showingQRCode = false
    @State private var failure: String?
    @State private var forgetting: CastSnapshot.Stage?

    private var stageAddress: String? {
        model.service?.stageMediaBase().map { "\($0)/tv" }
    }

    private var cast: CastSnapshot? { model.snapshot?.cast }

    var body: some View {
        Section {
            if let stageAddress {
                LabeledContent("Address") {
                    Text(stageAddress).textSelection(.enabled).font(.body.monospaced())
                }
                HStack {
                    Button("Copy Address") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(stageAddress, forType: .string)
                    }
                    Button("Show QR Code") { showingQRCode = true }
                }
            } else {
                Text("Connect this Mac to a network to show the TV address.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Cadenza TV")
        } footer: {
            Text("Open this address in a TV browser on the same network. No account or HTTPS setup is needed.")
        }
        .sheet(isPresented: $showingQRCode) {
            if let stageAddress {
                StageQRCodeSheet(address: stageAddress, image: qrImage(for: stageAddress))
            }
        }

        Section {
            ForEach(cast?.pendingStages ?? [], id: \.receiverId) { pending in
                LabeledContent(pending.name) {
                    HStack {
                        Text(pending.pin).font(.title3.monospacedDigit().bold())
                        Button("Approve") { approve(pin: pending.pin) }
                            .accessibilityLabel("Approve \(pending.name)")
                    }
                }
            }
            if (cast?.pendingStages ?? []).isEmpty {
                Text("No TV is waiting. Open the TV address to start pairing.").foregroundStyle(.secondary)
            }
        } header: {
            Text("Waiting for Approval")
        }

        Section {
            ForEach(cast?.stages ?? [], id: \.receiverId) { stage in
                LabeledContent(
                    stage.name, value: stage.status?.text ?? (stage.transmitting ? "Playing audio" : "Connected")
                )
                .contextMenu {
                    Button("Forget This TV", role: .destructive) { forgetting = stage }
                }
            }
            if (cast?.stages ?? []).isEmpty {
                Text("No approved TV is connected.").foregroundStyle(.secondary)
            }
            Picker("Audio format", selection: $transmitFormat) {
                Text("Transcode (Auto)").tag(CastTransmitChannelFormat.transcodeAuto)
                Text("Bitstream (raw PCM)").tag(CastTransmitChannelFormat.bitstream)
            }
        } header: {
            Text("Approved TVs")
        } footer: {
            Text(
                "Transcode (Auto) sends stereo as AAC and 5.1 as AC-3 when the AC-3 encoder is installed. "
                    + "Bitstream sends uncompressed PCM, which uses more network bandwidth."
            )
        }
        Section {
            TextField("App ID", text: $webLoaderAppId, prompt: Text("DashCast or another URL-loading app"))
        } header: {
            Text("Experimental Web Loader")
        } footer: {
            Text(
                "A Cast app that opens a web address, such as DashCast. Cadenza then opens its own /tv page on the TV "
                    + "instead of streaming audio to the Default Media Receiver. Leave empty to stream audio normally."
            )
        }
        .alert(
            "Cadenza Could Not Approve the TV",
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
        .confirmationDialog(
            "Forget \(forgetting?.name ?? "this TV")?",
            isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Forget TV", role: .destructive) {
                if let forgetting { model.service?.forgetStage(receiverId: forgetting.receiverId) }
                forgetting = nil
            }
            Button("Cancel", role: .cancel) { forgetting = nil }
        } message: {
            Text("The TV pairs again the next time it opens the address.")
        }
    }

    private func approve(pin: String) {
        do {
            try model.service?.approveStage(pin: pin)
        } catch {
            failure = error.localizedDescription
        }
    }

    private func qrImage(for value: String) -> NSImage? {
        let generator = CIFilter.qrCodeGenerator()
        generator.message = Data(value.utf8)
        generator.correctionLevel = "M"
        guard let output = generator.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let image = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width), height: CGFloat(image.height)))
    }
}

private struct StageQRCodeSheet: View {
    let address: String
    let image: NSImage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Scan this code with a TV browser").font(.title2.bold())
            if let image {
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 280, height: 280)
                    .accessibilityLabel("QR code for \(address)")
            }
            Text(address).font(.body.monospaced()).textSelection(.enabled)
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(minWidth: 420, minHeight: 460)
    }
}
