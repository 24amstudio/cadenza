import Foundation

/// Music shows region and storefront prompts as sheets or dialogs on its windows. While one is open, Music's controls do
/// not answer, so a missing song means Music is blocked, not that its page is still loading.
enum MusicModalBlock {
    /// `roleNames` holds the role and subrole of a window and of its children.
    static func isBlocked(roleNames: [String]) -> Bool {
        roleNames.contains { $0 == "AXSheet" || $0 == "AXDialog" }
    }
}
