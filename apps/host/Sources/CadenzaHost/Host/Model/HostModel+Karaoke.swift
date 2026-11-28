import Foundation

extension HostModel {
    func setKaraokeOutput(_ target: VideoOutputTarget) {
        submit(CommandAction(kind: "video.output", videoOutput: target.rawValue))
    }

    func singControl(_ kind: String, vocalPercent: Int? = nil) {
        guard let occurrence = snapshot?.current?.occurrenceId else { return }
        submit(CommandAction(kind: kind, occurrenceId: occurrence, vocalPercent: vocalPercent))
    }

    private func submit(_ action: CommandAction) {
        guard !controlling, let service else { return }
        controlling = true
        Task { @MainActor in
            defer { controlling = false }
            let frame = Frame(type: "command", commandId: UUID().uuidString, action: action)
            do {
                let result = try await service.executeCommand(frame, actor: "host")
                if result.outcome == "rejected" {
                    showError("The Host did not apply the change", result.message ?? "Try again.")
                }
            } catch {
                showError("The Host did not apply the change", error.localizedDescription)
            }
        }
    }
}
