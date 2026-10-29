import Foundation

struct PairedRemote: Identifiable {
    let id: String
    let name: String
    let revoked: Bool
    var status: SessionStatus? = nil
}
