extension HostSnapshot {
    func permitsHeartbeat(comparedTo previous: HostSnapshot) -> Bool {
        guard !playing, !previous.playing else { return false }
        var current = self
        var prior = previous
        current.sequence = 0
        prior.sequence = 0
        current.hostTimeMs = 0
        prior.hostTimeMs = 0
        current.current?.sampledAtHostMs = 0
        prior.current?.sampledAtHostMs = 0
        return current == prior
    }
}
