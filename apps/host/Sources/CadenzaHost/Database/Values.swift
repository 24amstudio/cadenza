import Foundation

enum SQLValue: Sendable, Equatable {
    case text(String)
    case integer(Int64)
    case null

    var string: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    var integer: Int64? {
        if case .integer(let value) = self { return value }
        return nil
    }
}

typealias SQLRow = [String: SQLValue]

enum DatabaseRole: Equatable {
    case main
    case logs
}
