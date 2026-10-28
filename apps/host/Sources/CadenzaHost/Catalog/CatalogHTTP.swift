import Foundation

final class AppleHTTP: NSObject, URLSessionTaskDelegate, Sendable {
    private let hosts: Set<String> = ["music.apple.com", "amp-api.music.apple.com", "api.music.apple.com"]

    func data(_ request: URLRequest, maximum: Int) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, url.scheme == "https", hosts.contains(url.host ?? "") else {
            throw CadenzaError.failure("catalog_unavailable", "Invalid Apple catalog address.")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw CadenzaError.failure("catalog_unavailable", "The catalog returned an invalid response.")
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximum else {
                throw CadenzaError.failure("catalog_unavailable", "The catalog response exceeded its size limit.")
            }
            data.append(byte)
        }
        guard data.count <= maximum else {
            throw CadenzaError.failure("catalog_unavailable", "The catalog response exceeded its size limit.")
        }
        return (data, response)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(request.url?.scheme == "https" && hosts.contains(request.url?.host ?? "") ? request : nil)
    }
}
