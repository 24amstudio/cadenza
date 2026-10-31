import Foundation

struct HostPrompt: Identifiable {
    let id = identifier()
    let title: String
    let message: String
}
