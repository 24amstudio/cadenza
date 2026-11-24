import AppKit
import UniformTypeIdentifiers

/// Saves rows to a file the user chooses and copies them to the pasteboard.
@MainActor
enum LogExport {
    enum Format {
        case text, json

        var type: UTType { self == .json ? .json : .plainText }
        var fileExtension: String { self == .json ? "json" : "txt" }
    }

    /// Returns the saved file name, or nil when the user cancelled.
    static func save(_ rows: [LogRow], as format: Format) throws -> String? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.type]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue =
            "Cadenza Host Logs \(rows.last?.day ?? "")".trimmingCharacters(in: .whitespaces) + "."
            + format.fileExtension
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        switch format {
        case .text: try Data(LogTranscript.text(rows).utf8).write(to: url, options: .atomic)
        case .json: try LogTranscript.json(rows).write(to: url, options: .atomic)
        }
        return url.lastPathComponent
    }

    /// Saves the mirrored log file with every retained generation, oldest first. Returns the saved name, or nil when the
    /// user cancelled.
    static func saveDiagnostics(_ mirror: LogMirror) throws -> String? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Cadenza Host Diagnostics.log"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try mirror.diagnosticsData().write(to: url, options: .atomic)
        return url.lastPathComponent
    }

    static func copy(_ rows: [LogRow]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(LogTranscript.text(rows), forType: .string)
    }
}
