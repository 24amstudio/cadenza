import Foundation

/// Downloads the Sing archive into a file this process owns. Only an HTTP 200 response is accepted.
enum SingModelDownloader {
    static func download(from url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let transfer = SingModelTransfer(progress: progress)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                transfer.start(url: url, continuation: continuation)
            }
        } onCancel: {
            transfer.cancel()
        }
    }
}

private final class SingModelTransfer: @unchecked Sendable {
    private let lock = NSLock()
    private let progress: @Sendable (Double) -> Void
    private var task: URLSessionDownloadTask?
    private var observation: NSKeyValueObservation?
    private var continuation: CheckedContinuation<URL, Error>?
    private var cancelled = false

    init(progress: @escaping @Sendable (Double) -> Void) {
        self.progress = progress
    }

    func start(url: URL, continuation: CheckedContinuation<URL, Error>) {
        lock.lock()
        defer { lock.unlock() }
        // Cancellation can arrive before the transfer exists, so it is recorded and checked here.
        guard !cancelled else {
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        let task = URLSession.shared.downloadTask(with: url) { [self] temporary, response, error in
            finish(temporary: temporary, response: response, error: error)
        }
        self.task = task
        observation = task.progress.observe(\.fractionCompleted, options: [.new]) { [progress] value, _ in
            progress(value.fractionCompleted)
        }
        task.resume()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    // URLSession deletes its temporary file when this handler returns, so the file is moved out first.
    private func finish(temporary: URL?, response: URLResponse?, error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        observation = nil
        lock.unlock()
        guard let continuation else { return }
        if let error {
            let isCancellation = (error as NSError).code == NSURLErrorCancelled
            continuation.resume(throwing: isCancellation ? CancellationError() : error)
            return
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, let temporary else {
            continuation.resume(throwing: CadenzaError.failure("sing_model", "The Sing model could not be downloaded."))
            return
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadenza-sing-\(UUID().uuidString).tar.gz")
        do {
            try FileManager.default.moveItem(at: temporary, to: destination)
            continuation.resume(returning: destination)
        } catch {
            continuation.resume(throwing: error)
        }
    }
}
