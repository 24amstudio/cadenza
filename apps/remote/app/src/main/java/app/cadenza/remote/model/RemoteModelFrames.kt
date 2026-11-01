package app.cadenza.remote.model

import android.os.SystemClock
import androidx.lifecycle.viewModelScope
import app.cadenza.remote.data.HostSnapshot
import app.cadenza.remote.data.Song
import app.cadenza.remote.data.UpdateConfiguration
import app.cadenza.remote.data.Wire
import app.cadenza.remote.data.counter
import app.cadenza.remote.data.nullableString
import app.cadenza.remote.data.objects
import app.cadenza.remote.media.SessionStatus
import app.cadenza.remote.network.PathMeasurement
import app.cadenza.remote.recommendation.RecommendationFeedback
import app.cadenza.remote.recommendation.RecommendationOutcome
import app.cadenza.remote.recommendation.RecommendationTrack
import app.cadenza.remote.recommendation.newRecommendationId
import app.cadenza.remote.updates.RemoteUpdater
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

internal suspend fun RemoteModel.receive(frame: JSONObject) {
    lastReceivedAt = SystemClock.elapsedRealtime()
    when (frame.getString("type")) {
        "session.status" -> applySessionStatus(frame.getJSONObject("status"))
        "recommendation.result" -> applyRecommendationResult(frame)
        "host.update.status" -> applyHostUpdateStatus(frame)
        "heartbeat" -> {
            if (frame.optString("host_epoch") == mutable.value.snapshot?.hostEpoch) {
                lastHeartbeatAt = lastReceivedAt
            } else {
                connection?.send(Wire.frame("state.get").put("request_id", id()))
            }
        }
        "welcome" -> welcome(frame.getJSONObject("welcome"))
        "state" -> applyState(frame.getJSONObject("snapshot"))
        "clock" -> {
            val sample = frame.getJSONObject("clock")
            val sentAt = sample.getLong("sent_at_remote_ms")
            val measuredRtt = (SystemClock.elapsedRealtime() - sentAt).coerceAtLeast(0)
            pathMeasurements.record(
                PathMeasurement(
                    transport = if (transportMode == "ble") "ble" else "lan",
                    rttMs = measuredRtt,
                    lossPercent = 0.0,
                    energyPercentPerHour = null,
                    confidence = "low",
                    sampleAgeMs = SystemClock.elapsedRealtime(),
                ),
            )
            clock.observe(
                sample.counter("sent_at_remote_ms"),
                sample.counter("received_at_host_ms"),
                sample.counter("sent_at_host_ms"),
                SystemClock.elapsedRealtime(),
            )
            mutable.update { it.copy(clockUncertaintyMs = clock.uncertaintyMs.takeIf { clock.ready }) }
        }
        "search.result" -> {
            val requestId = frame.nullableString("request_id")
            when {
                requestId == null -> Unit
                requestId == searchId -> {
                    searchTimeout?.cancel()
                    val songs = frame.getJSONArray("songs").objects().map(Wire::song)
                    mutable.update { it.copy(results = songs, searching = false) }
                    correctIfNeeded(songs)
                }
                requestId == correctionId -> {
                    val songs = frame.getJSONArray("songs").objects().map(Wire::song)
                    mutable.update { it.copy(correctedResults = songs) }
                }
            }
        }
        "search.suggestions" ->
            if (frame.nullableString("request_id") == suggestionId) {
                val terms = frame.optJSONArray("terms")?.let { items -> (0 until items.length()).map { items.getString(it) } }
                val songs = frame.optJSONArray("songs")?.objects()?.map(Wire::song)
                mutable.update { it.copy(suggestedTerms = terms.orEmpty(), suggestedSongs = songs.orEmpty()) }
            }
        "song.ready" ->
            if (frame.nullableString("request_id") == preparationId) {
                preparationTimeout?.cancel()
                val song = frame.getJSONObject("song")
                mutable.update { it.copy(preparing = false, preparedSong = song.getString("source") + ":" + song.getString("id")) }
            }
        "lyrics" -> {
            val document = Wire.lyrics(frame.getJSONObject("lyrics"))
            if (document.occurrenceId ==
                mutable.value.snapshot
                    ?.current
                    ?.occurrenceId
            ) {
                val notify = lyricUserInitiated && mutable.value.lyricsLoading
                recordLyricsDuration()
                lyricUserInitiated = false
                lyricsTimeout?.cancel()
                mutable.update {
                    it.copy(
                        lyrics = document,
                        lyricsLoading = false,
                        lyricsIssue = document.issue,
                        notice = if (notify) Notice("Music lyrics received") else it.notice,
                    )
                }
            }
        }
        "artwork" -> applyArtworkFrame(frame)
        "motion.chunk" -> applyMotionChunk(frame)
        "motion.unavailable" -> motionUnavailable(frame)
        "artwork.unavailable" -> frame.nullableString("artwork_url")?.let(::releaseArtwork)
        "analytics.credit" -> applyCredit(frame)
        "lyrics.unavailable" ->
            if (frame.nullableString("occurrence_id") ==
                mutable.value.snapshot
                    ?.current
                    ?.occurrenceId
            ) {
                if (lyricUserInitiated &&
                    mutable.value.lyricsLoading
                ) {
                    showError("Lyrics unavailable", frame.optString("message", "Open Music's lyrics pane and retry."))
                }
                recordLyricsDuration()
                lyricUserInitiated = false
                lyricsTimeout?.cancel()
                mutable.update {
                    it.copy(
                        lyricsLoading = false,
                        lyricsIssue = frame.optString("message", "Lyrics are unavailable."),
                    )
                }
            }
        "command.result" -> commandResultInternal(frame)
        "error" -> operationErrorInternal(frame)
        "operation.started" -> Unit
        else -> Unit
    }
}

internal suspend fun RemoteModel.welcome(value: JSONObject) {
    require(value.getInt("protocol_major") == 1) { "Update Host and Remote to compatible versions." }
    val invite = invitation
    val previous = mutable.value.profile
    val profile = hostProfileFromWelcome(value, activeEndpoint, invite, previous)
    val token = value.nullableString("token")
    withContext(ioDispatcher) {
        if (token != null) app.vault.save("host." + profile.hostId, token)
        app.database.saveProfile(profile)
        preferences.write("active_host" to profile.hostId, "client_name" to remoteName)
    }
    invitation = null
    pairingPin = null
    activeEndpoint?.let { endpoints.succeeded(it, SystemClock.elapsedRealtime()) }
    discovery?.close()
    discovery = null
    retryDelay = 1_000
    metadata.clear()
    val release = value.getJSONObject("updates")
    val updates = UpdateConfiguration(release.optString("repository"), release.optString("public_key_spki_base64"))
    try {
        RemoteUpdater.acceptConfiguration(app, updates)
    } catch (
        error: Exception,
    ) {
        showError("Check the update source", error.message ?: "Verify the release key in Cadenza Host.")
    }
    mutable.update {
        it.copy(
            profile = profile,
            clientName = remoteName,
            connected = true,
            hostUpdate = null,
            capabilities =
                value
                    .optJSONArray("capabilities")
                    ?.let { items ->
                        (0 until items.length()).map { items.getString(it) }.toSet()
                    }.orEmpty(),
            connecting = false,
            connectionIssue = null,
            updateConfiguration = RemoteUpdater.configuration(app),
        )
    }
    if (invite != null && transportMode == "hybrid") {
        val hello = handshake.frame(invite = null, profile = profile)
        hello.put("request_id", id())
        connection?.send(hello)
    }
    scheduleLogFlush()
    publishStatus()
    mutable.value.snapshot
        ?.current
        ?.occurrenceId
        ?.let { requestMotion(it) }
    if ("remote.configure" in mutable.value.capabilities) {
        connection?.send(
            Wire
                .frame("remote.configure")
                .put("request_id", id())
                .put("name", remoteName)
                .put("heartbeat", true),
        )
    }
    if ("recommendations.cree" in mutable.value.capabilities) {
        sendRecommendationPassport()
        requestRecommendation()
    }
    clockJob?.cancel()
    clockJob =
        viewModelScope.launch {
            repeat(5) {
                pingClock()
                delay(40)
            }
            while (true) {
                delay(5_000)
                if (SystemClock.elapsedRealtime() - lastStatusSentAt >= 15_000) publishStatus()
                if (SystemClock.elapsedRealtime() - lastReceivedAt > 10_000) {
                    connectionClosed(generation, "The Host stopped responding. Reconnecting…")
                    return@launch
                }
                if (mutable.value.snapshot?.playing == true ||
                    SystemClock.elapsedRealtime() - lastClockSentAt >= 30_000
                ) {
                    pingClock()
                }
            }
        }
    reloadStatistics()
    if (RemoteUpdater.due(app)) checkUpdates(automatic = true)
    val outstanding = withContext(ioDispatcher) { app.database.pending(profile) }
    for ((frame, key) in outstanding) {
        val commandId = frame.getString("command_id")
        // A restored seek has no trustworthy Host time, so it waits for the status answer instead of being predicted.
        if (!pending.containsKey(commandId)) trackPending(frame, key, optimisticIntent(frame, profile.remoteId, null, null))
        queryRequest(commandId)
    }
}

internal suspend fun RemoteModel.applyState(value: JSONObject) {
    val snapshot = enrichArtwork(Wire.snapshot(value))
    require(snapshot.hostId == mutable.value.profile?.hostId) { "Host identity did not match this pairing." }
    val previous = hostSnapshot
    if (previous?.hostEpoch == snapshot.hostEpoch && snapshot.sequence <= previous.sequence) return
    hostSnapshot = snapshot
    if (previous != null && previous.hostEpoch != snapshot.hostEpoch) clock.reset()
    val changedSong = snapshot.current?.occurrenceId != previous?.current?.occurrenceId
    if (changedSong || previous?.revision != snapshot.revision || SystemClock.elapsedRealtime() - lastCachedAt >= 5_000) {
        withContext(ioDispatcher) { app.database.saveState(snapshot.hostId, value) }
        lastCachedAt = SystemClock.elapsedRealtime()
        requestRecommendation()
    }
    mutable.update {
        it.copy(
            snapshot = snapshot.withOptimisticIntents(optimisticIntents()),
            lastStateAt = SystemClock.elapsedRealtime(),
            lyrics = if (changedSong) null else it.lyrics,
            lyricsIssue = if (changedSong) null else it.lyricsIssue,
            lyricsLoading = if (changedSong) false else it.lyricsLoading,
            motion = if (changedSong) null else it.motion,
        )
    }
    snapshot.current
        ?.song
        ?.artworkUrl
        ?.let(::requestArtwork)
    if (changedSong) snapshot.current?.occurrenceId?.let { requestMotion(it) }
    if (!foreground && !snapshot.playing) {
        endSessionStatus()
    }
    // This set only prevents duplicate catalog writes during one session. Keep
    // it bounded so a long-running Remote does not retain every song ever seen.
    if (metadata.size > 512) metadata.clear()
    val songs = snapshot.queue.map { it.song } + listOfNotNull(snapshot.current?.song)
    val new = songs.filter { metadata.add(it.source + ":" + it.id) }
    if (new.isNotEmpty()) withContext(ioDispatcher) { app.database.remember(snapshot.hostId, new) }
}

internal fun RemoteModel.enrichArtwork(snapshot: HostSnapshot): HostSnapshot = mutable.value.enrichArtwork(snapshot)

internal suspend fun RemoteModel.applyCredit(frame: JSONObject) {
    val host = mutable.value.profile?.hostId ?: return
    if (frame.optInt("play_count_delta", 0) == 1) {
        val song = frame.getJSONObject("song")
        val track = RecommendationTrack(song.getString("source"), song.getString("id"))
        val feedback = qualifiedRecommendationFeedback(frame, track)
        recommendationEngine.recordFeedback(feedback)
        sendRecommendationFeedback(feedback)
    }
    val cursor =
        withContext(ioDispatcher) {
            frame.optJSONObject("song_metadata")?.let { app.database.remember(host, listOf(Wire.song(it))) }
            app.database.applyCredit(host, frame)
        }
    connection?.send(Wire.frame("analytics.ack").put("sequence", cursor))
    reloadStatistics()
}

internal fun favoriteRecommendationFeedback(
    song: Song,
    saved: Boolean,
): RecommendationFeedback =
    RecommendationFeedback(
        recommendationId = newRecommendationId(),
        outcome = if (saved) RecommendationOutcome.FAVORITE else RecommendationOutcome.QUEUE_REMOVAL,
        track = RecommendationTrack(song.source, song.id, song.artist, song.album),
    )

private fun qualifiedRecommendationFeedback(
    frame: JSONObject,
    track: RecommendationTrack,
): RecommendationFeedback =
    RecommendationFeedback(
        recommendationId = frame.optString("recommendation_id", newRecommendationId()),
        outcome = RecommendationOutcome.QUALIFIED_PLAY,
        track = track,
        positionMs = frame.optLong("played_ms_delta", 0),
    )
