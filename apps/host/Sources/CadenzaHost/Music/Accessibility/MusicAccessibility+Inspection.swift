import AppKit
import ApplicationServices
import Foundation

/// Read-mostly inspection of Music's window chrome: the Lyrics button, the audio quality badge and AutoMix state.
extension MusicAccessibility {
    func press(_ element: AXUIElement, deadline: Int64) throws {
        try requireDeadline(deadline)
        guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
            throw CadenzaError.failure("music_unavailable", "Music did not accept the native button action.")
        }
    }

    func showLyrics(deadline: Int64) throws {
        beginRead(deadline: deadline)
        try showPanel(["lyrics", "show lyrics"], deadline: deadline)
    }

    func showPanel(_ names: [String], deadline: Int64) throws {
        let root = try root()
        let matches = shallow(
            root, maxDepth: 24, maxNodes: 4_000, skipping: [kAXRowRole, kAXCellRole, kAXMenuBarRole, kAXMenuRole]
        ) { element in
            let role = string(element, kAXRoleAttribute)
            guard [kAXButtonRole, kAXCheckBoxRole].contains(role),
                attribute(element, "AXHidden") as? Bool != true
            else { return false }
            let values = [
                string(element, kAXDescriptionAttribute),
                string(element, kAXTitleAttribute),
                string(element, kAXIdentifierAttribute),
                label(element),
            ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            return names.contains { name in
                values.contains { value in value == name || value.contains(name) }
            }
        }
        guard
            let button = matches.first(where: { (attribute($0, kAXValueAttribute) as? Bool) == true }) ?? matches.first
        else {
            throw CadenzaError.failure(
                "native_queue_unavailable", "The required Music sidebar button is not accessible.")
        }
        if (attribute(button, kAXValueAttribute) as? Bool) == true { return }
        try press(button, deadline: deadline)
    }

    func quality(currentTitle: String) -> String {
        beginRead()
        guard !currentTitle.isEmpty, let root = try? root() else { return "unknown" }
        // Music keeps the audio tier in its mini player badge. The toolbar this used to search does not hold it.
        let badge = shallow(
            root, maxDepth: 14, maxNodes: 1_500, skipping: [kAXMenuBarRole, kAXMenuRole, kAXRowRole, kAXCellRole]
        ) {
            string($0, kAXIdentifierAttribute) == "Music.miniPlayer.audioBadge"
        }.first
        guard let badge else { return "unknown" }
        let text = [kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute].map { string(badge, $0) }
            .joined(separator: " ")
        return MusicQuality.tier(forBadge: text)
    }

    func mixing(currentTitle: String) -> (active: Bool?, incomingTitle: String?) {
        beginRead()
        guard !currentTitle.isEmpty, let root = try? root() else { return (nil, nil) }
        let toolbars = shallow(root, maxDepth: 12, maxNodes: 1_200, skipping: [kAXMenuBarRole, kAXMenuRole]) {
            string($0, kAXRoleAttribute) == kAXToolbarRole
        }
        for toolbar in toolbars {
            let nodes = walk(toolbar)
            guard nodes.contains(where: { label($0).contains(currentTitle) }) else { continue }
            let active = nodes.contains(where: {
                string($0, kAXIdentifierAttribute) == "automix-transition"
                    && (attribute($0, kAXValueAttribute) as? Bool) == true
            })
            for node in nodes {
                let value = label(node)
                let prefix = "Mixing " + currentTitle + " into "
                if value.hasPrefix(prefix), value.count > prefix.count {
                    return (true, String(value.dropFirst(prefix.count)))
                }
            }
            if active { return (true, nil) }
        }
        return (nil, nil)
    }
}
