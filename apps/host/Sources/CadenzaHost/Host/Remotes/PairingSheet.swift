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
    private var pairingData: Data { PairingQRPayload(invitation: invitation).encoded }

    var body: some View {
        VStack(spacing: 20) {
            Text("Pair Cadenza Remote").font(.title.bold())
            Text("Open Cadenza Remote and scan this code. Pairing starts automatically after a valid scan.")
                .foregroundStyle(.secondary)
            if let image = qr(pairingData) {
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 400, height: 400)
                    .accessibilityLabel("Pairing QR code")
            }
            Text("\(invitation.host):\(invitation.port)").textSelection(.enabled)
            HStack {
                Button("Show larger QR") { showingLargeCode = true }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(minWidth: 560, minHeight: 560)
        .sheet(isPresented: $showingLargeCode) {
            PairingFullscreenSheet(image: qr(pairingData), host: invitation.host, port: invitation.port)
        }
    }

    private func qr(_ value: Data) -> NSImage? {
        let generator = CIFilter.qrCodeGenerator()
        generator.message = value
        generator.correctionLevel = "M"
        guard let output = generator.outputImage,
            let image = CIContext().createCGImage(
                output.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
                from: output.extent.applying(CGAffineTransform(scaleX: 8, y: 8)))
        else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width), height: CGFloat(image.height)))
    }
}

private struct PairingQRPayload {
    let invitation: PairingInvitation

    var encoded: Data {
        let address = Data(invitation.host.utf8)
        let secret = Data(invitation.secret.utf8)
        let fingerprintCharacters = Array(invitation.fingerprint)
        let fingerprint = stride(from: 0, to: fingerprintCharacters.count, by: 2).compactMap {
            UInt8(String(fingerprintCharacters[$0...($0 + 1)]), radix: 16)
        }
        guard fingerprint.count == 32 else { return Data() }
        var result = Data([0x43, 0x44, 0x5A, 0x50, 2])
        result.append(UInt8(address.count))
        result.append(address)
        result.append(UInt8((invitation.port >> 8) & 0xFF))
        result.append(UInt8(invitation.port & 0xFF))
        result.append(UInt8(secret.count))
        result.append(secret)
        result.append(contentsOf: fingerprint)
        let encoded = result.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return Data(("CDZP:" + encoded).utf8)
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
