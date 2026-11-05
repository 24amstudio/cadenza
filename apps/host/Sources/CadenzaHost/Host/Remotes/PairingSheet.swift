import AppKit
import CoreImage.CIFilterBuiltins
import Foundation
import SwiftUI

struct PairingSheetItem: Identifiable {
    var id: String { invitation.secret }
    let invitation: PairingInvitation
    init(_ invitation: PairingInvitation) { self.invitation = invitation }
}

struct PairingSheet: View {
    let invitation: PairingInvitation
    @Environment(\.dismiss) private var dismiss
    @State private var showingLargeCode = false
    private var pairingText: String? { PairingQRCode.text(for: invitation) }

    var body: some View {
        VStack(spacing: 20) {
            Text("Pair Cadenza Remote").font(.title.bold())
            Text("Open Cadenza Remote and scan this code. Pairing starts automatically after a valid scan.")
                .foregroundStyle(.secondary)
            if let pairingText, let image = qr(pairingText) {
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 400, height: 400)
                    .accessibilityLabel("Pairing QR code")
            }
            if let webAddress = PairingQRCode.webAddress(for: invitation) {
                Text("A regular camera opens " + webAddress).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text("\(invitation.host):\(invitation.port)").textSelection(.enabled)
            VStack(spacing: 6) {
                Text("Pair over Bluetooth with this PIN").font(.headline)
                Text(invitation.pin)
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityLabel("Bluetooth PIN " + invitation.pin.map(String.init).joined(separator: " "))
                Text("A new PIN appears every fifteen seconds.").foregroundStyle(.secondary)
            }
            HStack {
                Button("Show larger QR") { showingLargeCode = true }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(minWidth: 560, minHeight: 560)
        .sheet(isPresented: $showingLargeCode) {
            PairingFullscreenSheet(image: pairingText.flatMap(qr), host: invitation.host, port: invitation.port)
        }
    }

    private func qr(_ value: String) -> NSImage? {
        let generator = CIFilter.qrCodeGenerator()
        generator.message = Data(value.utf8)
        generator.correctionLevel = "M"
        guard let output = generator.outputImage,
            let image = CIContext().createCGImage(
                output.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
                from: output.extent.applying(CGAffineTransform(scaleX: 8, y: 8)))
        else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width), height: CGFloat(image.height)))
    }
}

private struct PairingFullscreenSheet: View {
    let image: NSImage?
    let host: String
    let port: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Scan this QR code on your Remote").font(.title.bold())
            Text("Keep the complete code inside the camera frame.")
            if let image {
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 680, height: 680)
                    .accessibilityLabel("Pairing QR code")
            }
            Text("\(host):\(port)").textSelection(.enabled)
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(36)
        .frame(minWidth: 800, minHeight: 800)
    }
}
