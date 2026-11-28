import Foundation

enum SingPageVisibility {
    static func shouldShow(
        target: VideoOutputTarget, currentOccurrenceId: String?, dismissedOccurrenceId: String?
    ) -> Bool {
        guard target == .hostDisplay, let currentOccurrenceId else { return false }
        return currentOccurrenceId != dismissedOccurrenceId
    }
}
