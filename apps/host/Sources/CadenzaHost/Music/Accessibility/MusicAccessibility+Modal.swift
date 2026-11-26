import ApplicationServices

extension MusicAccessibility {
    /// Whether Music has a sheet or dialog open on one of its windows. Reads are bounded, and an unreadable Music is not
    /// reported as blocked, so the caller keeps its normal failure.
    func modalBlocked() -> Bool {
        beginRead(deadline: monotonicMs() + 800)
        guard let application = try? root() else { return false }
        return children(application).contains { window in
            guard string(window, kAXRoleAttribute) == kAXWindowRole as String else { return false }
            let nested = children(window).flatMap { [string($0, kAXRoleAttribute), string($0, kAXSubroleAttribute)] }
            return MusicModalBlock.isBlocked(roleNames: [string(window, kAXSubroleAttribute)] + nested)
        }
    }
}
