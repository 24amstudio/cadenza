import Foundation
import Observation

/// The state behind the Logs view. It listens to the logger only between `start` and `stop`, which the view ties to
/// its own visibility, so nothing is retained or computed while the Logs section is closed.
@Observable
@MainActor
final class LogsModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    static let historyLimit = 500
    static let filterKey = "logViewerFilter"
    private static let facetLimit = 200

    private(set) var buffer = LogBuffer()
    private(set) var loadState = LoadState.idle
    private(set) var totalStored = 0
    /// Source values other than "host" and "remote" that exist in the stored logs.
    private(set) var otherSources: [String] = []
    private(set) var categories: [String] = []
    var filter: LogFilter {
        didSet {
            guard filter != oldValue else { return }
            saveFilter()
            scheduleReload(after: filter.search == oldValue.search ? .zero : .milliseconds(250))
        }
    }

    private var logger: HostLogger?
    private var reloadTask: Task<Void, Never>?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var saved =
            defaults.data(forKey: Self.filterKey).flatMap {
                try? JSONDecoder().decode(LogFilter.self, from: $0)
            } ?? LogFilter()
        // A saved time range would hide today's entries behind an old window, so each launch starts live.
        saved.time = .live
        filter = saved
    }

    var rows: [LogRow] { buffer.rows }
    var isPaused: Bool { buffer.isPaused }
    var isWatching: Bool { logger != nil }

    func start(logger: HostLogger?) {
        stop()
        guard let logger else { return }
        self.logger = logger
        logger.onFlush = { [weak self] firstId, batch in self?.ingest(firstId: firstId, batch: batch) }
        refreshFacets()
        scheduleReload(after: .zero)
    }

    func stop() {
        logger?.onFlush = nil
        logger = nil
        reloadTask?.cancel()
        reloadTask = nil
        buffer = LogBuffer()
        loadState = .idle
    }

    func togglePause() {
        if buffer.isPaused { buffer.resume() } else { buffer.pause() }
    }

    /// Empties the view. Stored logs stay where they are.
    func clearView() { buffer.clear() }

    func reload() {
        refreshFacets()
        scheduleReload(after: .zero)
    }

    func resetFilter() { filter = LogFilter() }

    /// Returns once the pending read of stored entries has finished.
    func settle() async { await reloadTask?.value }

    private func scheduleReload(after delay: Duration) {
        reloadTask?.cancel()
        guard logger != nil else { return }
        loadState = .loading
        reloadTask = Task { @MainActor [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.loadHistory()
        }
    }

    private func loadHistory() {
        guard let database = logger?.database else { return }
        do {
            let rows = try LogQueries.recent(database, filter: filter, limit: Self.historyLimit)
            buffer.replace(with: rows, newestStoredId: try LogQueries.newestId(database))
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func refreshFacets() {
        guard let database = logger?.database else { return }
        do {
            totalStored = try LogQueries.total(database)
            otherSources = try LogQueries.sources(database).filter { $0 != "host" && $0 != "remote" }
            categories = try LogQueries.categories(database)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func ingest(firstId: Int64, batch: [HostLogger.Entry]) {
        let now = Date()
        var accepted: [LogRow] = []
        for (offset, entry) in batch.enumerated() {
            let row = LogRow(id: firstId + Int64(offset), host: entry)
            remember(row)
            if filter.time.followsLiveEntries, filter.matches(row, now: now) { accepted.append(row) }
        }
        totalStored += batch.count
        if !accepted.isEmpty { buffer.append(accepted) }
    }

    /// A new category or source shows up in the filter menus without another query.
    private func remember(_ row: LogRow) {
        if !categories.contains(row.category), categories.count < Self.facetLimit {
            categories = (categories + [row.category]).sorted()
        }
        if row.source != "host", row.source != "remote", !otherSources.contains(row.source),
            otherSources.count < Self.facetLimit
        {
            otherSources = (otherSources + [row.source]).sorted()
        }
    }

    private func saveFilter() {
        if let data = try? JSONEncoder().encode(filter) { defaults.set(data, forKey: Self.filterKey) }
    }
}
