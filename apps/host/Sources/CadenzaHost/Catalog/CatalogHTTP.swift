import Foundation

final class AppleHTTP: Sendable {
    private let hosts: Set<String> = [
        "music.apple.com", "amp-api.music.apple.com", "api.music.apple.com", MotionPlaylist.host,
    ]
    // One session serves every request, so connections to Apple stay open between catalog calls.
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 30
        let delegate = RedirectGuard(hosts: hosts)
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    deinit { session.finishTasksAndInvalidate() }

    func data(_ request: URLRequest, maximum: Int) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, url.scheme == "https", hosts.contains(url.host ?? "") else {
            throw CadenzaError.failure("catalog_unavailable", "Invalid Apple catalog address.")
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw CadenzaError.failure("catalog_unavailable", "The catalog returned an invalid response.")
        }
        guard data.count <= maximum else {
            throw CadenzaError.failure("catalog_unavailable", "The catalog response exceeded its size limit.")
        }
        return (data, response)
    }
}

// URLSession uses this immutable delegate to refuse redirects off the fixed Apple origins.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    private let hosts: Set<String>

    init(hosts: Set<String>) { self.hosts = hosts }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(request.url?.scheme == "https" && hosts.contains(request.url?.host ?? "") ? request : nil)
    }
}
