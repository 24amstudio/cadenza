import CryptoKit
import Foundation

struct WebRemoteFile: Equatable {
    let url: URL
    let contentType: String
    let isHashedAsset: Bool
}

// Static files for the browser Remote. Only regular files inside the bundled directory with a listed type are served.
// The policy allows inline scripts by hash, so the page never needs unsafe-inline for scripts.
struct WebRemoteBundle {
    let root: URL
    let contentSecurityPolicy: String

    private static let contentTypes: [String: String] = [
        "html": "text/html; charset=utf-8",
        "js": "text/javascript; charset=utf-8",
        "css": "text/css; charset=utf-8",
        "json": "application/json; charset=utf-8",
        "svg": "image/svg+xml",
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "webp": "image/webp",
        "ico": "image/x-icon",
        "woff": "font/woff",
        "woff2": "font/woff2",
        "txt": "text/plain; charset=utf-8",
    ]

    init(root: URL) {
        self.root = root.standardizedFileURL
        let index = try? Data(contentsOf: root.appendingPathComponent("index.html"))
        let html = index.map { String(decoding: $0, as: UTF8.self) } ?? ""
        contentSecurityPolicy = Self.policy(scriptHashes: Self.inlineScriptHashes(in: html))
    }

    // Returns nil for any path that is not a listed file inside the bundle, including traversal and hidden names.
    func file(forRequestPath requestPath: String) -> WebRemoteFile? {
        guard let relative = Self.relativePath(forRequestPath: requestPath) else { return nil }
        let url = root.appendingPathComponent(relative).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { return nil }
        guard let contentType = Self.contentTypes[url.pathExtension.lowercased()] else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue
        else { return nil }
        return WebRemoteFile(url: url, contentType: contentType, isHashedAsset: relative.hasPrefix("_nuxt/"))
    }

    static func relativePath(forRequestPath requestPath: String) -> String? {
        let withoutQuery = requestPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first
        guard let target = withoutQuery.map(String.init), target.hasPrefix("/"),
            let decoded = target.removingPercentEncoding,
            !decoded.contains("\0"), !decoded.contains("\\")
        else { return nil }
        let components = decoded.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.contains(where: { $0.hasPrefix(".") }) else { return nil }
        return components.isEmpty ? "index.html" : components.joined(separator: "/")
    }

    // Each inline <script> body is hashed exactly as the browser sees it. Scripts that load a file are not inline.
    static func inlineScriptHashes(in html: String) -> [String] {
        guard
            let expression = try? NSRegularExpression(
                pattern: "<script(\\s[^>]*)?>([\\s\\S]*?)</script>", options: [.caseInsensitive])
        else { return [] }
        let source = html as NSString
        return expression.matches(in: html, range: NSRange(location: 0, length: source.length)).compactMap { match in
            // An absent attribute group is reported as NSNotFound, which is an empty opening tag, not an error.
            let openingRange = match.range(at: 1)
            let opening = openingRange.location == NSNotFound ? "" : source.substring(with: openingRange)
            guard !opening.lowercased().contains("src=") else { return nil }
            let body = source.substring(with: match.range(at: 2))
            let digest = SHA256.hash(data: Data(body.utf8))
            return "'sha256-\(Data(digest).base64EncodedString())'"
        }
    }

    static func policy(scriptHashes: [String]) -> String {
        let scripts = (["'self'"] + scriptHashes).joined(separator: " ")
        return [
            "default-src 'none'",
            "script-src \(scripts)",
            "style-src 'self' 'unsafe-inline'",
            "img-src 'self' data:",
            "connect-src 'self'",
            "font-src 'self'",
            "base-uri 'none'",
            "form-action 'none'",
            "frame-ancestors 'none'",
        ].joined(separator: "; ")
    }
}
