import Foundation
import Observation

/// Owns the Sing model on this Mac. A model is downloaded only when the user asks. The one exception is replacing an
/// installed model that no longer matches this build, which happens silently and only after verification.
@MainActor
@Observable
final class SingModelManager {
    typealias Fetch = @Sendable (URL, @escaping @Sendable (Double) -> Void) async throws -> URL

    enum State: Equatable {
        case notInstalled
        case downloading(progress: Double, isAutoUpdate: Bool)
        case ready(version: String, sizeBytes: Int64)
        case failed(String)
    }

    private(set) var state: State = .notInstalled
    /// The complete model on disk, if any. Sing and the Remote read this, not the transient download state.
    private(set) var installed: SingModelReceipt?
    let spec: SingModelSpec?
    var onInstalledChanged: (() -> Void)?
    private let location: SingModelLocation
    private let fetch: Fetch
    private var task: Task<Void, Never>?

    init(
        spec: SingModelSpec? = SingModelSpec.current(),
        location: SingModelLocation = .standard(),
        fetch: @escaping Fetch = { try await SingModelDownloader.download(from: $0, progress: $1) }
    ) {
        self.spec = spec
        self.location = location
        self.fetch = fetch
    }

    var isInstalled: Bool { installed != nil }

    /// Runs at every launch and after a Host update. A model that was never installed stays not installed.
    func reconcileOnLaunch() {
        // A service restart must not reset the state of a download that is still running.
        guard task == nil else { return }
        installed = location.installedReceipt()
        guard let installed else {
            state = .notInstalled
            return
        }
        state = .ready(version: installed.version, sizeBytes: installed.sizeBytes)
        guard let spec, installed.version != spec.version || installed.sha256 != spec.sha256 else { return }
        // A previously installed model that this build does not expect is replaced without asking the user.
        if spec.url != nil { download(isAutoUpdate: true) }
    }

    func download(isAutoUpdate: Bool = false) {
        guard task == nil else { return }
        guard let spec, let url = spec.url else {
            state = .failed("This build cannot download the Sing model. Use a release build.")
            return
        }
        state = .downloading(progress: 0, isAutoUpdate: isAutoUpdate)
        task = Task { @MainActor [weak self] in
            await self?.run(spec: spec, url: url)
        }
    }

    func cancel() {
        task?.cancel()
    }

    /// Deletes the installed model. The UI asks for confirmation first.
    func remove() throws {
        task?.cancel()
        let directory = location.installedDirectory
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        installed = nil
        state = .notInstalled
        onInstalledChanged?()
    }

    private func run(spec: SingModelSpec, url: URL) async {
        defer {
            task = nil
            onInstalledChanged?()
        }
        let location = location
        do {
            let archive = try await fetch(url) { [weak self] value in
                Task { @MainActor in self?.report(progress: value) }
            }
            let receipt = try await Task.detached(priority: .utility) {
                try await SingModelInstaller.install(archive: archive, spec: spec, location: location)
            }.value
            installed = receipt
            state = .ready(version: receipt.version, sizeBytes: receipt.sizeBytes)
        } catch is CancellationError {
            state = installed.map { .ready(version: $0.version, sizeBytes: $0.sizeBytes) } ?? .notInstalled
        } catch {
            // A failed replacement leaves any installed model in place, so Sing keeps using it.
            state = .failed(error.localizedDescription)
        }
    }

    private func report(progress value: Double) {
        guard case .downloading(_, let isAutoUpdate) = state else { return }
        state = .downloading(progress: value, isAutoUpdate: isAutoUpdate)
    }
}
