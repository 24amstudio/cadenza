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
    @State private var copied = false
    private var json: String { (try? String(decoding: Wire.encode(invitation), as: UTF8.self)) ?? "" }

    var body: some View {
        VStack(spacing: 20) {
            Text("Pair Cadenza Remote").font(.title.bold())
            Text("Scan this QR code on your tablet. It is valid for one Remote for five minutes.")
            if let image = qr(json) {
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 400, height: 400)
                    .accessibilityLabel("Pairing QR code")
            }
            Text("\(invitation.host):\(invitation.port)").textSelection(.enabled)
            HStack {
                Button(copied ? "Copied" : "Copy pairing details") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(json, forType: .string)
                    copied = true
                }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(minWidth: 560, minHeight: 560)
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
