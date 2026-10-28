import Foundation

final class GitHubHTTP: NSObject, URLSessionTaskDelegate, Sendable {
    private let hosts: Set<String> = [
        "api.github.com", "github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com",
    ]

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.urlCredentialStorage = nil
        config.httpCookieStorage = nil
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    private func request(_ address: String) throws -> URLRequest {
        guard let url = URL(string: address), valid(url) else {
            throw CadenzaError.failure("update", "Invalid GitHub address.")
        }
        var request = URLRequest(url: url)
        request.setValue("Cadenza-Host", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        return request
    }

    private func valid(_ url: URL) -> Bool {
        url.scheme == "https" && hosts.contains(url.host ?? "") && url.user == nil
            && url.password == nil && (url.port == nil || url.port == 443)
    }

    func bytes(_ address: String, maximum: Int) async throws -> Data {
        let session = session()
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request(address))
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw CadenzaError.failure(
                "update", "GitHub could not provide this release. Check the repository and try again.")
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximum else { throw CadenzaError.failure("update", "Release metadata is too large.") }
            data.append(byte)
        }
        return data
    }

    func download(
        _ address: String, to destination: URL, expectedSize: Int64,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request(address))
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw CadenzaError.failure("update", "The update package could not be downloaded.")
        }
        guard
            FileManager.default.createFile(
                atPath: destination.path, contents: nil, attributes: [.posixPermissions: 0o600])
        else {
            throw CadenzaError.failure("update", "Cannot create the staged download.")
        }
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        var buffer = Data()
        var count: Int64 = 0
        for try await byte in bytes {
            buffer.append(byte)
            count += 1
            guard count <= expectedSize else {
                throw CadenzaError.failure("update", "The update exceeded its signed size.")
            }
            if buffer.count >= 262_144 {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
                progress(Double(count) / Double(expectedSize))
            }
        }
        try handle.write(contentsOf: buffer)
        try handle.synchronize()
        guard count == expectedSize else { throw CadenzaError.failure("update", "The download was interrupted.") }
        progress(1)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(request.url.map(valid) == true ? request : nil)
    }
}
