import Foundation

/// One `Range` header for a single byte range. Multiple ranges and malformed headers are answered with the whole file,
/// the HTTP fallback for an ignored range. A start beyond the file is unsatisfiable.
enum ByteRange: Equatable {
    case full
    case partial(ClosedRange<Int64>)
    case unsatisfiable

    static func parse(_ header: String?, size: Int64) -> ByteRange {
        guard let header, header.hasPrefix("bytes="), size > 0 else { return size > 0 ? .full : .unsatisfiable }
        let spec = header.dropFirst("bytes=".count)
        guard !spec.contains(","), let dash = spec.firstIndex(of: "-") else { return .full }
        let first = String(spec[..<dash])
        let last = String(spec[spec.index(after: dash)...])
        if first.isEmpty {
            guard let length = Int64(last), length > 0 else { return .full }
            return .partial(max(0, size - length)...(size - 1))
        }
        guard let start = Int64(first), start >= 0 else { return .full }
        guard start < size else { return .unsatisfiable }
        if last.isEmpty { return .partial(start...(size - 1)) }
        guard let requestedEnd = Int64(last), requestedEnd >= start else { return .full }
        return .partial(start...min(requestedEnd, size - 1))
    }
}
