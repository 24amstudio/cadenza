package app.cadenza.remote.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.lerp
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import app.cadenza.remote.data.CurrentPlayback
import app.cadenza.remote.data.LyricDocument
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.RemoteState
import app.cadenza.remote.model.isStale
import kotlin.math.abs

internal fun activeLyricIndex(
    document: LyricDocument?,
    occurrence: String?,
    positionMs: Long,
    synchronized: Boolean,
): Int {
    if (!synchronized || occurrence == null || document?.occurrenceId != occurrence) return -1
    // Provider end markers can leave short gaps between lines. Keep the most
    // recently started line active through those gaps so highlighting and
    // following stay aligned with the playback timeline.
    return document.lines.indexOfLast { it.endMs > it.startMs && it.startMs <= positionMs }
}

private fun activeWordIndex(
    line: app.cadenza.remote.data.LyricLine,
    positionMs: Long,
): Int = line.words.indexOfLast { it.endMs > it.startMs && it.startMs <= positionMs && positionMs < it.endMs }

@Composable
private fun LyricText(
    line: app.cadenza.remote.data.LyricLine,
    currentPosition: Long,
    distanceFromActive: Int,
    onWordClick: ((Long) -> Unit)? = null,
) {
    val activeLine = distanceFromActive == 0
    val activeWord = if (activeLine) activeWordIndex(line, currentPosition) else -1
    val activeLineColor by animateColorAsState(
        if (activeLine) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
        animationSpec = tween(220, easing = FastOutSlowInEasing),
        label = "lyric-line-color",
    )
    val inactiveBlur by animateDpAsState(
        when {
            distanceFromActive == 0 -> 0.dp
            distanceFromActive == 1 -> 2.dp
            else -> 4.dp
        },
        animationSpec = tween(260, easing = FastOutSlowInEasing),
        label = "lyric-line-blur",
    )
    val lineAlpha by animateFloatAsState(
        when (distanceFromActive) {
            0 -> 1f
            1 -> 0.72f
            2 -> 0.48f
            else -> 0.28f
        },
        animationSpec = tween(260, easing = FastOutSlowInEasing),
        label = "lyric-line-alpha",
    )
    val lineScale by animateFloatAsState(
        if (activeLine) 1.04f else 1f,
        animationSpec = tween(260, easing = FastOutSlowInEasing),
        label = "lyric-line-scale",
    )
    val wordFocus by animateFloatAsState(
        activeWord.toFloat(),
        animationSpec = tween(180, easing = FastOutSlowInEasing),
        label = "lyric-word-focus",
    )
    val text: AnnotatedString =
        if (line.words.isEmpty()) {
            AnnotatedString(line.text)
        } else {
            buildAnnotatedString {
                line.words.forEachIndexed { index, word ->
                    val emphasis = (1f - abs(index - wordFocus)).coerceIn(0f, 1f)
                    val wordColor =
                        lerp(MaterialTheme.colorScheme.onSurface, MaterialTheme.colorScheme.primary, emphasis)
                    val wordAlpha = 0.62f + (0.38f * emphasis)
                    withStyle(
                        SpanStyle(
                            color = wordColor.copy(alpha = wordAlpha),
                            fontWeight = if (index == activeWord) FontWeight.Bold else FontWeight.Normal,
                        ),
                    ) { append(word.text) }
                }
            }
        }
    if (line.words.isNotEmpty() && onWordClick != null) {
        FlowRow(
            Modifier
                .fillMaxWidth()
                .graphicsLayer {
                    alpha = lineAlpha
                    scaleX = lineScale
                    scaleY = lineScale
                },
            horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            line.words.forEachIndexed { index, word ->
                val emphasis = (1f - abs(index - wordFocus)).coerceIn(0f, 1f)
                Text(
                    word.text,
                    style = if (activeLine) MaterialTheme.typography.headlineLarge else MaterialTheme.typography.headlineMedium,
                    fontWeight = if (index == activeWord) FontWeight.Bold else FontWeight.Normal,
                    color =
                        lerp(MaterialTheme.colorScheme.onSurface, MaterialTheme.colorScheme.primary, emphasis)
                            .copy(alpha = 0.62f + 0.38f * emphasis),
                    modifier =
                        Modifier
                            .blur(inactiveBlur)
                            .clickable(role = Role.Button) { onWordClick(word.startMs) }
                            .semantics { contentDescription = "Seek to ${word.text.trim()}" },
                )
            }
        }
    } else {
        Text(
            text,
            style =
                when (distanceFromActive) {
                    0 -> MaterialTheme.typography.headlineLarge
                    1 -> MaterialTheme.typography.headlineMedium
                    else -> MaterialTheme.typography.titleLarge
                },
            fontWeight = if (activeLine && activeWord < 0) FontWeight.Bold else FontWeight.Normal,
            color = activeLineColor,
            modifier =
                Modifier
                    .graphicsLayer {
                        alpha = lineAlpha
                        scaleX = lineScale
                        scaleY = lineScale
                    }.blur(inactiveBlur),
        )
    }
}

@Composable
fun LyricsScreen(
    model: RemoteModel,
    state: RemoteState,
    onExit: () -> Unit = {},
) {
    val current = state.snapshot?.current
    KeepScreenAwake(state.snapshot?.playing == true && current != null)
    val occurrence = current?.occurrenceId
    val document = state.lyrics?.takeIf { it.occurrenceId == occurrence }
    val stale = !state.connected || model.isStale()
    val currentPosition = position(model, 100)
    val artwork = rememberArtwork(current?.song?.artworkUrl)
    val backdrop =
        artwork?.accent?.let {
            Brush.verticalGradient(
                listOf(
                    it.copy(alpha = 0.30f),
                    MaterialTheme.colorScheme.surface.copy(alpha = 0.94f),
                    MaterialTheme.colorScheme.surface,
                ),
            )
        } ?: Brush.verticalGradient(listOf(MaterialTheme.colorScheme.primaryContainer, MaterialTheme.colorScheme.surface))
    LaunchedEffect(occurrence, state.connected) {
        if (occurrence != null && state.connected && document == null && !state.lyricsLoading) {
            model.loadLyrics(userInitiated = false)
        }
    }
    BoxWithConstraints(
        Modifier.fillMaxSize().background(backdrop),
    ) {
        val expanded = maxWidth >= 720.dp
        val compactHeader = maxWidth < 400.dp && LocalDensity.current.fontScale >= 1.5f
        Column(Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onExit) { Icon(cadenzaVector(CadenzaIcon.BACK), contentDescription = "Back to player") }
                if (compactHeader) {
                    Spacer(Modifier.weight(1f))
                } else {
                    Text("Now playing", Modifier.weight(1f), style = MaterialTheme.typography.headlineSmall, maxLines = 1)
                }
                FilterChip(
                    selected = true,
                    onClick = onExit,
                    label = { Text("Lyrics") },
                    leadingIcon = { Icon(cadenzaVector(CadenzaIcon.LYRICS), contentDescription = null) },
                )
            }
            if (expanded && current != null) {
                Row(Modifier.weight(1f).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(28.dp)) {
                    Column(Modifier.weight(0.42f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Artwork(artwork, Modifier.widthIn(max = 260.dp).fillMaxWidth().aspectRatio(1f))
                        TrackIdentity(current, state.profile?.remoteId)
                        Spacer(Modifier.weight(1f))
                        PlaybackTimeline(model, state, currentPosition)
                        PlaybackTransport(model, state, compact = true)
                    }
                    LyricsContent(model, state, document, currentPosition, stale, Modifier.weight(0.58f).fillMaxHeight())
                }
            } else {
                current?.let { CompactTrackIdentity(it, state.profile?.remoteId, artwork) }
                LyricsContent(model, state, document, currentPosition, stale, Modifier.weight(1f).fillMaxWidth())
                if (current != null) {
                    PlaybackTimeline(model, state, currentPosition)
                    PlaybackTransport(model, state, compact = true)
                }
            }
        }
    }
}

@Composable
private fun TrackIdentity(
    current: CurrentPlayback,
    remoteId: String?,
    modifier: Modifier = Modifier,
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(current.song.title, style = MaterialTheme.typography.headlineSmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Text(current.song.artist, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
        val requester = if (remoteId != null && current.requestedBy == remoteId) "you" else current.requesterName
        Text("Requested by $requester", style = MaterialTheme.typography.labelMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun CompactTrackIdentity(
    current: CurrentPlayback,
    remoteId: String?,
    artwork: ArtworkData?,
) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Artwork(artwork, Modifier.size(56.dp))
        TrackIdentity(current, remoteId, Modifier.weight(1f))
    }
}

@Composable
private fun LyricTranslation(
    translation: String?,
    index: Int,
    active: Int,
    revealed: Boolean,
    modifier: Modifier = Modifier,
) {
    val activeLine = index == active
    // Lines nearest the active line lead the reveal.
    val revealDelay = abs(index - active).coerceAtMost(6) * 40
    val emphasis by animateFloatAsState(
        if (activeLine) 1f else 0f,
        animationSpec = tween(260, easing = FastOutSlowInEasing),
        label = "lyric-translation-emphasis",
    )
    val translationAlpha by animateFloatAsState(
        if (activeLine) 1f else 0.68f,
        animationSpec = tween(260, easing = FastOutSlowInEasing),
        label = "lyric-translation-alpha",
    )
    val translationBlur by animateDpAsState(
        when {
            activeLine -> 0.dp
            active < 0 || abs(index - active) == 1 -> 2.dp
            else -> 4.dp
        },
        animationSpec = tween(260, easing = FastOutSlowInEasing),
        label = "lyric-translation-blur",
    )
    AnimatedVisibility(
        visible = translation != null && revealed,
        modifier = modifier,
        enter =
            fadeIn(tween(320, delayMillis = revealDelay, easing = FastOutSlowInEasing)) +
                expandVertically(
                    tween(320, delayMillis = revealDelay, easing = FastOutSlowInEasing),
                    expandFrom = Alignment.Top,
                ),
        exit = fadeOut(tween(160)) + shrinkVertically(tween(160)),
    ) {
        Text(
            translation.orEmpty(),
            style = lerp(MaterialTheme.typography.titleMedium, MaterialTheme.typography.titleLarge, emphasis),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.graphicsLayer { alpha = translationAlpha }.blur(translationBlur),
        )
    }
}

@Composable
internal fun LyricsContent(
    model: RemoteModel,
    state: RemoteState,
    document: LyricDocument?,
    currentPosition: Long,
    stale: Boolean,
    modifier: Modifier = Modifier,
) {
    val occurrence = state.snapshot?.current?.occurrenceId
    key(occurrence) {
        val list = rememberLazyListState()
        var following by rememberSaveable { mutableStateOf(true) }
        // Translations already in the document reveal together when this song's lyrics first appear.
        // Later arrivals animate on their own, and lines that scroll into view afterward appear as-is.
        val translationReveal = remember { MutableTransitionState(false) }
        LaunchedEffect(document != null) { translationReveal.targetState = document != null }
        val active = activeLyricIndex(document, occurrence, currentPosition, !stale)
        val userScroll =
            remember {
                object : NestedScrollConnection {
                    override fun onPreScroll(
                        available: Offset,
                        source: NestedScrollSource,
                    ): Offset {
                        if (source == NestedScrollSource.UserInput && available.y != 0f) following = false
                        return Offset.Zero
                    }
                }
            }
        LaunchedEffect(active, document?.revision, following) {
            if (following && active >= 0) {
                // Wait for the lazy list to report a real viewport before seeking it.
                // A single frame is not enough when artwork and lyrics enter together;
                // otherwise the first active line can be missed until a manual scroll.
                repeat(3) {
                    withFrameNanos { }
                }
                val viewport = list.layoutInfo.viewportEndOffset - list.layoutInfo.viewportStartOffset
                if (viewport > 0) {
                    val offset = -(viewport / 2).coerceAtLeast(0)
                    list.animateScrollToItem(active, offset)
                }
            }
        }
        Column(modifier, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (stale) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        cadenzaVector(CadenzaIcon.WIFI_OFF),
                        contentDescription = "Reconnecting to Host",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(20.dp),
                    )
                    Text("Synchronization paused.", style = MaterialTheme.typography.bodyMedium)
                }
            }
            when {
                document == null && state.lyricsLoading -> {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                        Text("Loading lyrics…")
                    }
                }
                document == null || document.lines.isEmpty() -> {
                    Text(
                        state.lyricsIssue ?: document?.issue ?: if (occurrence == null) {
                            "Play a song to see its lyrics."
                        } else {
                            "Lyrics are unavailable. Open the lyrics pane in Cadenza Host and retry."
                        },
                    )
                    ActionButton("Retry lyrics", pending = state.lyricsLoading, enabled = state.connected && occurrence != null) {
                        model.loadLyrics()
                    }
                }
                else -> {
                    LyricsSource(document)
                    when (document.level) {
                        1 -> Text("Lyrics without timing", style = MaterialTheme.typography.bodyMedium)
                        2 -> Text("Timed by line", style = MaterialTheme.typography.bodyMedium)
                        3 -> Text("Timed by line and word", style = MaterialTheme.typography.bodyMedium)
                    }
                    document.issue?.let {
                        Text(it, style = MaterialTheme.typography.bodyMedium)
                        ActionButton("Reload lyrics", pending = state.lyricsLoading, enabled = state.connected) { model.loadLyrics() }
                    }
                    if (!following) {
                        TextButton(onClick = { following = true }) { Text("Follow current line") }
                    }
                    LazyColumn(
                        modifier = Modifier.weight(1f).fillMaxWidth().nestedScroll(userScroll),
                        state = list,
                        verticalArrangement = Arrangement.spacedBy(24.dp),
                    ) {
                        itemsIndexed(document.lines, key = { _, line -> line.id }) { index, line ->
                            val canSeek =
                                state.connected && !stale && mayInterruptPlayback(state) &&
                                    line.endMs > line.startMs
                            Column(
                                Modifier
                                    .fillMaxWidth()
                                    .clickable(
                                        enabled = canSeek && line.words.isEmpty(),
                                        role = Role.Button,
                                    ) {
                                        model.command(
                                            org.json
                                                .JSONObject()
                                                .put("kind", "playback.seek")
                                                .put("occurrence_id", occurrence)
                                                .put("position_ms", line.startMs),
                                            "playback.seek",
                                        )
                                    }.padding(vertical = 6.dp)
                                    .semantics(mergeDescendants = true) {
                                        selected = index == active
                                        if (canSeek) contentDescription = "Seek to ${line.text}"
                                    },
                                verticalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                LyricText(
                                    line,
                                    currentPosition,
                                    if (active < 0) 3 else abs(index - active),
                                    onWordClick =
                                        if (canSeek && line.words.isNotEmpty()) {
                                            { time ->
                                                model.command(
                                                    org.json
                                                        .JSONObject()
                                                        .put("kind", "playback.seek")
                                                        .put("occurrence_id", occurrence)
                                                        .put("position_ms", time),
                                                    "playback.seek",
                                                )
                                            }
                                        } else {
                                            null
                                        },
                                )
                                line.romanized?.takeIf { it.isNotBlank() }?.let {
                                    val romanizedStyle =
                                        if (index == active) {
                                            MaterialTheme.typography.titleLarge
                                        } else {
                                            MaterialTheme.typography.titleMedium
                                        }
                                    Text(
                                        it,
                                        style = romanizedStyle,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.blur(if (index == active) 0.dp else 2.dp),
                                    )
                                }
                                LyricTranslation(
                                    translation = line.translation,
                                    index = index,
                                    active = active,
                                    revealed = translationReveal.targetState,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LyricsSource(document: LyricDocument) {
    val source =
        when (document.source) {
            "lrclib" -> "LRCLIB"
            "apple_music" -> "Apple Music"
            else -> "Host provider"
        }
    val label =
        "$source · " +
            when (document.translationSource) {
                "apple" -> "English translation from Apple Music"
                "machine" -> "English machine translation"
                "apple_and_machine" -> "English translation from Apple Music and on-device translation"
                "original" -> "Original lyrics"
                else -> "Lyrics"
            }
    AnimatedContent(
        targetState = label,
        transitionSpec = { fadeIn(tween(320)) togetherWith fadeOut(tween(160)) },
        label = "lyrics-source",
    ) { text ->
        Text(
            text,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
