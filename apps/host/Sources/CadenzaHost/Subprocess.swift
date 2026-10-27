import Foundation

enum Subprocess {
    static func run(
        _ executable: String, _ arguments: [String], input: Data? = nil,
        timeout: TimeInterval = 2, environment: [String: String]? = nil
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let job = Job(
                executable: executable, arguments: arguments, input: input,
                timeout: timeout, environment: environment
            ) { result in continuation.resume(with: result) }
            job.start()
        }
    }

    // Process completion and timeout race. Only finish() may complete the continuation;
    // its NSLock protects that transition. The child writes to private regular files.
    private final class Job: @unchecked Sendable {
        private let process = Process()
        private let lock = NSLock()
        private var finished = false
        private let executable: String
        private let arguments: [String]
        private let input: Data?
        private let timeout: TimeInterval
        private let environment: [String: String]?
        private let completion: @Sendable (Result<Data, Error>) -> Void
        private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(identifier())

        init(
            executable: String, arguments: [String], input: Data?, timeout: TimeInterval,
            environment: [String: String]?, completion: @escaping @Sendable (Result<Data, Error>) -> Void
        ) {
            self.executable = executable
            self.arguments = arguments
            self.input = input
            self.timeout = timeout
            self.environment = environment
            self.completion = completion
        }

        func start() {
            do {
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]
                )
                let output = directory.appendingPathComponent("output")
                let error = directory.appendingPathComponent("error")
                let source = directory.appendingPathComponent("input")
                try Data().write(to: output, options: [.atomic])
                try Data().write(to: error, options: [.atomic])
                try (input ?? Data()).write(to: source, options: [.atomic])
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.environment = environment
                process.standardInput = try FileHandle(forReadingFrom: source)
                process.standardOutput = try FileHandle(forWritingTo: output)
                process.standardError = try FileHandle(forWritingTo: error)
                process.terminationHandler = { [self] _ in finish(timedOut: false) }
                try process.run()
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) { [self] in
                    finish(timedOut: true)
                }
            } catch {
                finish(error: error)
            }
        }

        private func finish(timedOut: Bool = false, error: Error? = nil) {
            lock.lock()
            if finished { lock.unlock(); return }
            finished = true
            lock.unlock()
            defer {
                process.terminationHandler = nil
                try? FileManager.default.removeItem(at: directory)
            }
            if timedOut {
                if process.isRunning { process.terminate() }
                completion(.failure(CadenzaError.failure("outcome_unknown", "Music did not confirm the action before its deadline.")))
                return
            }
            if let error { completion(.failure(error)); return }
            do {
                let output = try Data(contentsOf: directory.appendingPathComponent("output"))
                guard output.count <= Wire.maximumMessageBytes else {
                    throw CadenzaError.failure("invalid_state", "The system response exceeded its size limit.")
                }
                guard process.terminationStatus == 0 else {
                    let data = try Data(contentsOf: directory.appendingPathComponent("error"))
                    let message = String(decoding: data.prefix(2_000), as: UTF8.self)
                    throw CadenzaError.failure("music_unavailable", message.isEmpty ? "The system command failed." : message)
                }
                completion(.success(output))
            } catch { completion(.failure(error)) }
        }
    }
}
