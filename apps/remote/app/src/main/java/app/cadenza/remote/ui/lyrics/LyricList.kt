package app.cadenza.remote.ui.lyrics

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.unit.dp
import app.cadenza.remote.data.LyricDocument
import app.cadenza.remote.data.LyricsTextSize

private const val LINE_WITH_WORDS = "words"
private const val LINE_PLAIN = "plain"

/** What the list needs about playback. Lines receive only the primitives derived from it. */
internal class LyricPlayback(
    val positionMs: Long,
    val active: List<Int>,
    val sweep: SweepTarget?,
    val synced: Boolean,
    val clock: LyricsClock,
)

/**
 * The lyric lines. Each line is keyed by its stable id and typed by whether it carries words. Level 1 lyrics are plain
 * text; levels 2 and 3 recede by distance from the active lines and level 3 sweeps the sounding word.
 */
@Composable
internal fun LyricList(
    document: LyricDocument,
    playback: LyricPlayback,
    list: LazyListState,
    userScroll: NestedScrollConnection,
    reduced: Boolean,
    translationRevealed: Boolean,
    textSize: LyricsTextSize,
    canSeek: (Int) -> Boolean,
    onSeek: (Long) -> Unit,
    modifier: Modifier = Modifier,
) {
    val timed = document.level >= 2
    val wordTimed = document.level == 3
    BoxWithConstraints(modifier) {
        // Timed lyrics pad both ends so the first and last lines can reach the centre of the viewport.
        val edge = if (timed) maxHeight * 0.4f else 0.dp
        LazyColumn(
            modifier = Modifier.fillMaxSize().nestedScroll(userScroll),
            state = list,
            contentPadding = PaddingValues(top = edge, bottom = maxOf(edge, 24.dp)),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            itemsIndexed(
                document.lines,
                key = { _, line -> line.id },
                contentType = { _, line -> if (line.words.isEmpty()) LINE_PLAIN else LINE_WITH_WORDS },
            ) { index, line ->
                val receding = timed && playback.synced
                val state =
                    LyricLineState(
                        tier = if (receding) lyricTier(index, playback.active) else TIER_ACTIVE,
                        active = index in playback.active,
                        receding = receding,
                        wordTimed = wordTimed,
                        sweepWord = playback.sweep?.takeIf { it.line == index }?.word ?: -1,
                        litWords =
                            when {
                                !wordTimed -> 0
                                !playback.synced -> line.words.size
                                else -> litWordCount(line.words, playback.positionMs)
                            },
                    )
                LyricLineItem(
                    line = line,
                    state = state,
                    clock = playback.clock,
                    reduced = reduced,
                    translationRevealed = translationRevealed,
                    seekable = canSeek(index),
                    onSeek = { onSeek(line.startMs) },
                    textSize = textSize,
                )
            }
        }
    }
}
