package app.cadenza.remote.tv

/**
 * What the TV stage shows. [reduce] is pure: it takes one message and the elapsed-realtime clock, and returns the next
 * state. The socket and audio code never change this state directly, so every transition has a test.
 */
internal data class TvStageState(
    val phase: Phase = Phase.CONNECTING,
    val pin: String? = null,
    val pinExpiresAtMs: Long? = null,
    val suite: TvStageSuite? = null,
    val video: TvStageMessage.Video? = null,
    val playing: Boolean = false,
    val clockPositionMs: Long = 0L,
    val clockSinceMs: Long = 0L,
    val clockRate: Double = 1.0,
    val error: String? = null,
) {
    enum class Phase { CONNECTING, PAIRING, READY, OFFLINE }

    /** The track position at [elapsedMs]: the last synced position, advanced while playing and never past the end. */
    fun positionAt(elapsedMs: Long): Long {
        val advanced = if (playing) ((elapsedMs - clockSinceMs).coerceAtLeast(0L) * clockRate).toLong() else 0L
        val position = (clockPositionMs + advanced).coerceAtLeast(0L)
        val duration = suite?.durationMs ?: 0L
        return if (duration > 0L) position.coerceAtMost(duration) else position
    }

    fun reduce(
        message: TvStageMessage,
        elapsedMs: Long,
    ): TvStageState =
        when (message) {
            is TvStageMessage.Pairing ->
                copy(
                    phase = Phase.PAIRING,
                    pin = message.pin,
                    pinExpiresAtMs = elapsedMs + message.expiresInMs,
                )

            is TvStageMessage.Accepted -> copy(phase = Phase.READY, pin = null, pinExpiresAtMs = null)

            is TvStageMessage.Suite ->
                copy(
                    phase = Phase.READY,
                    suite = message.suite,
                    video = null,
                    playing = true,
                    clockPositionMs = 0L,
                    clockSinceMs = elapsedMs,
                    clockRate = 1.0,
                )

            is TvStageMessage.Prefetch -> this

            is TvStageMessage.Optimistic ->
                copy(
                    playing = message.isPlaying,
                    clockPositionMs = message.targetPositionMs,
                    clockSinceMs = elapsedMs,
                    clockRate = message.playbackRate,
                )

            is TvStageMessage.Clock ->
                copy(
                    clockPositionMs = message.actualPositionMs,
                    clockSinceMs = elapsedMs,
                    clockRate = 1.0,
                )

            is TvStageMessage.Video -> copy(video = message)
        }

    fun disconnected(): TvStageState = copy(phase = Phase.OFFLINE, playing = false)
}
