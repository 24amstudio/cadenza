import Foundation

/// A listening signal the Host records for one paired Remote. A Remote's own choices weigh more than what the queue
/// gives it later.
enum TasteSignal: String, CaseIterable, Sendable {
    case playNow = "play_now"
    case playNext = "play_next"
    case enqueue
    case promotion
    case autoplayPlay = "autoplay_play"
    case completion
    case earlySkip = "early_skip"

    /// The signal a queue command implies. Only the three queue requests carry taste.
    init?(commandKind: String) {
        switch commandKind {
        case "queue.play_now": self = .playNow
        case "queue.play_next": self = .playNext
        case "queue.enqueue": self = .enqueue
        default: return nil
        }
    }

    /// The weight in tenths, so it is stored as an integer and read back exactly.
    var weightTenths: Int {
        switch self {
        case .playNow: 30
        case .playNext: 20
        case .enqueue: 15
        case .promotion: 10
        case .autoplayPlay: 20
        case .completion: 15
        case .earlySkip: -20
        }
    }
}

enum TasteBucket: String, Sendable {
    case morning, afternoon, evening
    case lateNight = "late_night"

    static func bucket(for date: Date, calendar: Calendar = .current) -> TasteBucket {
        switch calendar.component(.hour, from: date) {
        case 5..<12: .morning
        case 12..<17: .afternoon
        case 17..<22: .evening
        default: .lateNight
        }
    }
}

/// Keeps weighted listening signals per Remote, and derives each Remote's artist affinities from them. A signal's weight
/// halves every two weeks, so recent taste dominates. Affinities are derived on each read rather than stored, so they
/// never go stale.
extension TasteSignal {
    /// A play now of a song Music is set to play after the queue is an AutoPlay choice. Other requests keep their signal.
    static func played(_ signal: TasteSignal, fromAutoPlay: Bool) -> TasteSignal {
        signal == .playNow && fromAutoPlay ? .autoplayPlay : signal
    }

    /// How a song ended for its requester. Under 25 seconds and before 80 percent of a known length is an early skip, and
    /// 80 percent or more is a completion. Radio has no length, so it earns neither.
    static func ending(positionMs: Int64, durationMs: Int64?, isLiveRadio: Bool) -> TasteSignal? {
        guard !isLiveRadio, let durationMs, durationMs > 0 else { return nil }

        let fraction = Double(positionMs) / Double(durationMs)

        if fraction >= 0.8 { return .completion }
        if positionMs < 25_000 { return .earlySkip }

        return nil
    }
}

@MainActor
struct TasteLedger {
    static let halfLifeMs = 14.0 * 86_400_000
    static let readLimit = 2_000

    let database: Database

    func record(
        remoteId: String, signal: TasteSignal, artist: String, track: String, at date: Date, bucket: TasteBucket
    ) throws {
        _ = try database.run(
            """
            INSERT INTO remote_taste_events(remote_id,signal,artist_key,track_key,weight_tenths,bucket,occurred_at_ms)
            VALUES(?,?,?,?,?,?,?)
            """,
            [
                .text(remoteId), .text(signal.rawValue), .text(artist), .text(track),
                .integer(Int64(signal.weightTenths)), .text(bucket.rawValue),
                .integer(Int64(date.timeIntervalSince1970 * 1_000)),
            ])
    }

    /// Each artist's decayed affinity for one Remote, from -1 to 1. A single play now (3.0) reads as 1.
    func affinities(remoteId: String, now: Date) throws -> [String: Double] {
        let rows = try database.query(
            "SELECT artist_key,weight_tenths,occurred_at_ms FROM remote_taste_events WHERE remote_id=? ORDER BY occurred_at_ms DESC LIMIT ?",
            [.text(remoteId), .integer(Int64(Self.readLimit))])
        let nowMs = Double(now.timeIntervalSince1970 * 1_000)
        var sums: [String: Double] = [:]

        for row in rows {
            guard let artist = row["artist_key"]?.string, let tenths = row["weight_tenths"]?.integer,
                let occurred = row["occurred_at_ms"]?.integer
            else { continue }
            let age = max(0, nowMs - Double(occurred))
            sums[artist, default: 0] += Double(tenths) / 10 * pow(0.5, age / Self.halfLifeMs)
        }

        return sums.mapValues { min(max($0 / 3, -1), 1) }
    }

    /// Artists this Remote has played, not skipped, in a time-of-day bucket.
    func artists(remoteId: String, bucket: TasteBucket) throws -> Set<String> {
        let rows = try database.query(
            "SELECT DISTINCT artist_key FROM remote_taste_events WHERE remote_id=? AND bucket=? AND weight_tenths>0",
            [.text(remoteId), .text(bucket.rawValue)])
        return Set(rows.compactMap { $0["artist_key"]?.string })
    }
}
