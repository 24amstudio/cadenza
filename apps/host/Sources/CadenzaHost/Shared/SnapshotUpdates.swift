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

    // While playback continues, only time-derived fields change: the sample time, the position, and the queue wait
    // estimates. A Remote can extrapolate those from its last full state. A seek, a track change, or an edit is a real
    // change and still needs a full state.
    func changedOnlyByPlaybackTime(since sent: HostSnapshot, toleranceMs: Int64 = 1_000) -> Bool {
        guard playing, sent.playing, let now = current, let before = sent.current,
            now.occurrenceId == before.occurrenceId, now.sampledAtHostMs >= before.sampledAtHostMs
        else { return false }
        let expectedPositionMs = before.positionMs + (now.sampledAtHostMs - before.sampledAtHostMs)
        guard abs(now.positionMs - expectedPositionMs) <= toleranceMs else { return false }
        return withoutPlaybackTime == sent.withoutPlaybackTime
    }

    private var withoutPlaybackTime: HostSnapshot {
        var value = self
        value.sequence = 0
        value.hostTimeMs = 0
        value.totalRemainingMs = nil
        value.current?.sampledAtHostMs = 0
        value.current?.positionMs = 0
        value.queue = value.queue.map { entry in
            var entry = entry
            entry.estimatedWaitMs = nil
            entry.estimatedStartHostMs = nil
            entry.estimateStatus = nil
            return entry
        }
        return value
    }
}
