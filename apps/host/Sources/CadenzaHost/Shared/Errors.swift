import Foundation

enum CadenzaError: LocalizedError, Sendable {
    case failure(String, String)

    var code: String {
        switch self {
        case .failure(let code, _): return code
        }
    }

    var errorDescription: String? {
        switch self {
        case .failure(_, let message): return message
        }
    }
}
