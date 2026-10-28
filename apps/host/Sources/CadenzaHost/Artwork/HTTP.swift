import Foundation

final class ArtworkHTTP: NSObject, URLSessionTaskDelegate, Sendable {
    func data(_ request: URLRequest, maximum: Int) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, ArtworkProvider.isAllowedURL(url.absoluteString) else {
            throw CadenzaError.failure("artwork_unavailable", "The artwork address is invalid.")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 8
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw CadenzaError.failure("artwork_unavailable", "The artwork response was invalid.")
        }
        guard response.statusCode == 200 else {
            throw CadenzaError.failure("artwork_unavailable", "Apple's artwork CDN returned HTTP \(response.statusCode).")
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximum else {
                throw CadenzaError.failure("artwork_unavailable", "The artwork response is too large.")
            }
            data.append(byte)
        }
        return (data, response)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(
            request.url.flatMap { ArtworkProvider.isAllowedURL($0.absoluteString) ? request : nil })
    }
}
