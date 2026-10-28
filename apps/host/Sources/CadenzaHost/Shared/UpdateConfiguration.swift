import Foundation

struct UpdateConfiguration: Codable, Sendable {
    var repository: String = ""
    var publicKeySpkiBase64: String = ""
}
