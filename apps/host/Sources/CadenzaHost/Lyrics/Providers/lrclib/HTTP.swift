import Foundation

final class LRCLIBHTTP: NSObject, URLSessionTaskDelegate, Sendable {
    func data(_ request: URLRequest, maximum: Int) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, url.scheme == "https", url.host == "lrclib.net", url.user == nil else {
            throw CadenzaError.failure("lyrics_provider", "The lyric provider address is invalid.")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 8
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw CadenzaError.failure("lyrics_provider", "The lyric provider returned an invalid response.")
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximum else { throw CadenzaError.failure("lyrics_provider", "The lyric response is too large.") }
            data.append(byte)
        }
        return (data, response)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) { completionHandler(request.url?.scheme == "https" && request.url?.host == "lrclib.net" ? request : nil) }
}
