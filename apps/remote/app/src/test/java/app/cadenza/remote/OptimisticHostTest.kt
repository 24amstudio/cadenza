package app.cadenza.remote

import app.cadenza.remote.data.CurrentPlayback
import app.cadenza.remote.model.OptimisticIntent
import app.cadenza.remote.model.withOptimisticIntents
import org.junit.Assert.assertEquals
import org.junit.Test

class OptimisticHostTest {
    private val occurrence = "occurrence-a"
    private val host =
        testSnapshot(
            playing = true,
            volume = 40,
            current =
                CurrentPlayback(
                    occurrenceId = occurrence,
                    entryId = null,
                    requestedBy = null,
                    requesterName = "",
                    song = testSong("current"),
                    positionMs = 10_000,
                    sampledAtHostMs = 0,
                ),
            queue = listOf(testEntry("a"), testEntry("b"), testEntry("c")),
        )

    @Test
    fun pauseSeekAndVolumeShowTheIntendedPlaybackBeforeTheHostAnswers() {
        val shown =
            host.withOptimisticIntents(
                listOf(
                    OptimisticIntent.Playing(false),
                    OptimisticIntent.Seek(occurrence, 60_000, appliedAtHostMs = 500),
                    OptimisticIntent.Volume(75),
                ),
            )

        assertEquals(false, shown.playing)
        assertEquals(75, shown.volume)
        assertEquals(60_000L, shown.current?.positionMs)
        assertEquals(500L, shown.current?.sampledAtHostMs)
    }

    @Test
    fun aSeekForAnotherOccurrenceDoesNotMoveTheCurrentSong() {
        assertEquals(host, host.withOptimisticIntents(listOf(OptimisticIntent.Seek("other", 60_000, 500))))
    }

    @Test
    fun queueEditsShowUntilTheIntentIsDroppedAndThenRevert() {
        val intents = listOf(OptimisticIntent.Move("c", beforeEntryId = "a"), OptimisticIntent.Remove("b"))

        assertEquals(listOf("c", "a"), host.withOptimisticIntents(intents).queue.map { it.id })
        assertEquals(listOf("a", "b", "c"), host.withOptimisticIntents(emptyList()).queue.map { it.id })
    }

    @Test
    fun aMoveToTheEndAndPlayNextLandWhereTheHostWouldPlaceThem() {
        val shown =
            host.withOptimisticIntents(
                listOf(
                    OptimisticIntent.Move("a", beforeEntryId = null),
                    OptimisticIntent.Enqueue("command-1", testSong("next"), requestedBy = "remote", next = true),
                    OptimisticIntent.Enqueue("command-2", testSong("last"), requestedBy = "remote", next = false),
                ),
            )

        assertEquals(listOf("pending:command-1", "b", "c", "a", "pending:command-2"), shown.queue.map { it.id })
    }
}
