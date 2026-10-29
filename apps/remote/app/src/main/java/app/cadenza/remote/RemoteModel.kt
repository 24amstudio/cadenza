package app.cadenza.remote

import android.app.Application
import android.os.SystemClock
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.cadenza.remote.data.ClockSync
import app.cadenza.remote.data.EffectiveTransportDecision
import app.cadenza.remote.data.HostProfile
import app.cadenza.remote.data.HostSnapshot
import app.cadenza.remote.data.LyricDocument
import app.cadenza.remote.data.PairingInvitation
import app.cadenza.remote.data.Song
import app.cadenza.remote.data.SongStatistic
import app.cadenza.remote.data.ThemePreference
import app.cadenza.remote.data.TransportPathStatus
import app.cadenza.remote.data.UpdateConfiguration
import app.cadenza.remote.data.Wire
import app.cadenza.remote.data.counter
import app.cadenza.remote.data.deviceName
import app.cadenza.remote.data.nullableString
import app.cadenza.remote.data.objects
import app.cadenza.remote.network.BleConnection
import app.cadenza.remote.network.EndpointPool
import app.cadenza.remote.network.HostConnection
import app.cadenza.remote.network.HostDiscovery
import app.cadenza.remote.network.HybridConnection
import app.cadenza.remote.network.LocalEndpoint
import app.cadenza.remote.network.NetworkMonitor
import app.cadenza.remote.network.PathMeasurement
import app.cadenza.remote.network.PathMeasurementService
import app.cadenza.remote.network.PrioritizedFrameQueue
import app.cadenza.remote.network.RemoteConnection
import app.cadenza.remote.network.RemoteStatusPublisher
import app.cadenza.remote.updates.RemoteUpdater
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.util.UUID

class RemoteModel(
    application: Application,
    private val ioDispatcher: CoroutineDispatcher,
) : AndroidViewModel(application) {
    constructor(application: Application) : this(application, Dispatchers.IO)

    private val app = application as CadenzaApplication
    internal val preferences = app.settings
    private val mediaActions = RemoteMediaActions({ mutable.value }, ::command)
    private val mediaSession = RemoteMediaSession(app, mediaActions::handle)
    val mediaToken get() = mediaSession.token
    internal val mutable = MutableStateFlow(RemoteState())
    val state = mutable.asStateFlow()
    internal val clock = ClockSync()
    internal var connection: RemoteConnection? = null
    internal var transportMode = "lan"
    internal var transportPreference = "balanced"
    private var generation = 0
    internal var foreground = false
    private var receiveJob: Job? = null
    internal var invitation: PairingInvitation? = null
    private var remoteName = deviceName(application)
    private var reconnect: Job? = null
    private var clockJob: Job? = null
    private var lastReceivedAt = 0L
    internal var lastHeartbeatAt = 0L
    private var lastClockSentAt = 0L
    internal var lastStatusSentAt = 0L
    private var retryDelay = 1_000L
    internal var searchId: String? = null
    internal var preparationId: String? = null
    internal var searchTimeout: Job? = null
    internal var preparationTimeout: Job? = null
    internal var lyricsTimeout: Job? = null
    internal var lyricRequestId: String? = null
    internal var lyricUserInitiated = false
    internal var discovery: HostDiscovery? = null
    private var lastDiscoveredAt = 0L
    private val endpoints = EndpointPool()
    internal val statusPublisher = RemoteStatusPublisher(app)
    internal val pathMeasurements = PathMeasurementService()
    private val handshake = RemoteHandshake(app, ioDispatcher) { remoteName }
    private var activeEndpoint: LocalEndpoint? = null
    internal val networkMonitor =
        NetworkMonitor(app) {
            viewModelScope.launch {
                if (foreground && mutable.value.loaded && mutable.value.profile != null) {
                    discovery?.close()
                    discovery = null
                    if (!mutable.value.connected) {
                        startDiscovery()
                        if (!mutable.value.connecting) connect()
                    }
                }
            }
        }
    private var lastCachedAt = 0L
    internal val pending = mutableMapOf<String, PendingCommand>()
    internal val statusChecks = mutableSetOf<String>()
    private val frameQueue = PrioritizedFrameQueue()
    private val frameSignal = Channel<Unit>(Channel.UNLIMITED)
    private val metadata = mutableSetOf<String>()
    internal val artworkRequests = mutableSetOf<String>()
    internal val mutableState get() = mutable
    internal val updateApp get() = app
    internal val updateDispatcher get() = ioDispatcher
    internal val updateScope get() = viewModelScope

    internal data class PendingCommand(
        val frame: JSONObject,
        val key: String,
        val timer: Job,
        var sentAtElapsedMs: Long = 0,
    )

    init {
        app.unpinSession = ::endSessionStatus
        app.mediaAction = mediaActions::handle
        viewModelScope.launch {
            state.map(SessionStatus::from).distinctUntilChanged().collect { SessionNotification(app).update(it, mediaToken) }
        }
        viewModelScope.launch {
            state.map(mediaActions::sessionState).distinctUntilChanged().collect(mediaSession::update)
        }
        viewModelScope.launch {
            for (ignored in frameSignal) {
                val item = frameQueue.poll() ?: continue
                val version = item.version
                if (version == generation) {
                    receiveJob =
                        launch {
                            try {
                                receive(item.frame)
                            } catch (error: CancellationException) {
                                throw error
                            } catch (error: Exception) {
                                if (version == generation) {
                                    showError("Could not apply Host data", error.message ?: "Reconnect and retry.")
                                    disconnect()
                                }
                            }
                        }
                    receiveJob?.join()
                    receiveJob = null
                }
            }
        }
        viewModelScope.launch {
            try {
                val host = preferences.getString("active_host", null)
                val profile = withContext(ioDispatcher) { host?.let(app.database::profile) }
                val updates = RemoteUpdater.configuration(app)
                val staged = RemoteUpdater.staged(app)
                val cached = withContext(ioDispatcher) { profile?.let { app.database.cachedState(it.hostId) } }
                val library = withContext(ioDispatcher) { app.library.load() }
                remoteName = preferences.getString("client_name", null)?.takeIf { it.isNotBlank() && it.length <= 80 } ?: remoteName
                val theme =
                    ThemePreference.entries.firstOrNull { it.name == preferences.getString("theme", null) } ?: ThemePreference.SYSTEM
                mutable.update {
                    it.copy(
                        loaded = true,
                        clientName = remoteName,
                        transportMode = preferences.getString("transport_mode", "lan") ?: "lan",
                        transportPreference = preferences.getString("transport_preference", "balanced") ?: "balanced",
                        theme = theme,
                        favorites = library.songs,
                        unreadableFavorites = library.unreadable,
                        profile = profile,
                        snapshot = cached,
                        updateConfiguration = updates,
                        stagedUpdate = staged?.absolutePath,
                    )
                }
                withContext(ioDispatcher) {
                    val last = preferences.getLong("last_maintenance", 0)
                    if (System.currentTimeMillis() - last >= 86_400_000) {
                        app.database.maintain()
                        preferences.write("last_maintenance" to System.currentTimeMillis().toString())
                    }
                }
                reloadStatistics()
                if (foreground && profile != null) {
                    startDiscovery()
                    connect()
                }
                if (BuildConfig.AUTOMATIC_UPDATES && RemoteUpdater.configuration(app).repository.isNotBlank()) {
                    checkUpdates(automatic = true)
                }
            } catch (error: Exception) {
                mutable.update { it.copy(loaded = true) }
                showError("Storage needs attention", error.message ?: "Your data was preserved. Restart Cadenza and retry.")
            }
        }
    }

    fun setForeground(visible: Boolean) {
        foreground = visible
        if (visible) networkMonitor.start() else networkMonitor.close()
        if (visible) startDiscovery()
        if (visible && mutable.value.loaded && mutable.value.profile != null && !mutable.value.connected) connect()
        if (!visible) {
            discovery?.close()
            discovery = null
            mutable.update { it.copy(prompt = null) }
            if (!maintainBackgroundSessionInternal()) {
                endSessionStatus()
                disconnect()
            }
        }
    }

    private fun startDiscovery() {
        if (!foreground || !mutable.value.loaded || discovery != null) return
        discovery =
            HostDiscovery(app) { host ->
                val profile = mutable.value.profile ?: return@HostDiscovery
                val now = SystemClock.elapsedRealtime()
                if (host.hostId != profile.hostId) return@HostDiscovery
                endpoints.offer(LocalEndpoint(host.address, host.port), now)
                if (mutable.value.connected || mutable.value.connecting ||
                    now - lastDiscoveredAt < 3_000
                ) {
                    return@HostDiscovery
                }
                lastDiscoveredAt = now
                discovery?.close()
                discovery = null
                connect()
            }.also { it.start() }
    }

    fun pair(
        payload: ByteArray,
        name: String,
    ) {
        try {
            val invite =
                if (Wire.isCompactInvitation(payload)) {
                    Wire.invitation(payload)
                } else {
                    Wire.invitation(String(payload, Charsets.UTF_8))
                }
            require(name.trim().length in 1..80) { "Enter the name that should appear beside your requests." }
            require(name.none { it.isISOControl() }) { "Use a name without control characters." }
            invitation = invite
            endpoints.clear()
            remoteName = name.trim()
            connect()
        } catch (error: Exception) {
            showError("Could not scan QR", error.message ?: "Scan a current Host QR code.")
        }
    }

    fun connect() {
        try {
            openConnection()
        } catch (error: Exception) {
            disconnect()
            showError("Could not connect", error.message ?: "Check pairing details and reconnect.")
        }
    }

    fun setTransportMode(mode: String) {
        require(mode in setOf("lan", "ble", "hybrid")) { "Unsupported transport mode." }
        if (transportMode == mode) return
        transportMode = mode
        preferences.write("transport_mode" to mode)
        mutable.update { it.copy(transportMode = mode) }
        if (mutable.value.connected || mutable.value.connecting) connect()
    }

    fun setTransportPreference(preference: String) {
        require(preference in setOf("latency", "host_efficiency", "remote_efficiency", "reliability", "balanced")) {
            "Unsupported transport preference."
        }
        transportPreference = preference
        preferences.write("transport_preference" to preference)
        mutable.update { it.copy(transportPreference = preference) }
        if (mutable.value.connected) publishStatus()
    }

    private fun openConnection() {
        disconnect()
        val invite = invitation
        val profile = mutable.value.profile
        val fallback = LocalEndpoint(invite?.host ?: profile?.address ?: return, invite?.port ?: profile?.port ?: return)
        val endpoint = if (invite != null) fallback else endpoints.next(fallback, SystemClock.elapsedRealtime())
        activeEndpoint = endpoint
        val host = endpoint.address
        val port = endpoint.port
        val fingerprint = invite?.fingerprint ?: profile?.fingerprint ?: return
        val version = ++generation
        clock.reset()
        lastHeartbeatAt = 0
        mutable.update { it.copy(connecting = true, connectionIssue = null) }
        connection =
            if (transportMode == "ble") {
                BleConnection(
                    getApplication(),
                    opened = {
                        viewModelScope.launch {
                            if (version != generation) return@launch
                            sendHandshake(invite, profile, version)
                        }
                    },
                    received = { frame ->
                        val accepted = frameQueue.offer(PrioritizedFrameQueue.Item(version, frame))
                        if (!accepted) {
                            viewModelScope.launch { connectionClosed(version, "Host messages arrived faster than they could be applied.") }
                        } else {
                            frameSignal.trySend(Unit)
                        }
                    },
                    closed = { message -> viewModelScope.launch { connectionClosed(version, message) } },
                )
            } else if (transportMode == "hybrid") {
                HybridConnection(
                    getApplication(),
                    host,
                    port,
                    fingerprint,
                    invite?.certificateDerBase64 ?: requireNotNull(profile).certificateDerBase64,
                    opened = {
                        viewModelScope.launch {
                            if (version != generation) return@launch
                            sendHandshake(invite, profile, version)
                        }
                    },
                    received = { frame ->
                        val accepted = frameQueue.offer(PrioritizedFrameQueue.Item(version, frame))
                        if (!accepted) {
                            viewModelScope.launch { connectionClosed(version, "Host messages arrived faster than they could be applied.") }
                        } else {
                            frameSignal.trySend(Unit)
                        }
                    },
                    closed = { message -> viewModelScope.launch { connectionClosed(version, message) } },
                )
            } else {
                HostConnection(
                    host,
                    port,
                    fingerprint,
                    invite?.certificateDerBase64 ?: requireNotNull(profile).certificateDerBase64,
                    opened = {
                        viewModelScope.launch {
                            if (version != generation) return@launch
                            try {
                                sendHandshake(invite, profile, version)
                            } catch (error: Exception) {
                                if (version != generation) return@launch
                                showError("Pair this Remote again", error.message ?: "The saved credential could not be read.")
                                disconnect()
                            }
                        }
                    },
                    received = { frame ->
                        val accepted = frameQueue.offer(PrioritizedFrameQueue.Item(version, frame))
                        if (!accepted) {
                            viewModelScope.launch { connectionClosed(version, "Host messages arrived faster than they could be applied.") }
                        } else {
                            frameSignal.trySend(Unit)
                        }
                    },
                    closed = { message -> viewModelScope.launch { connectionClosed(version, message) } },
                )
            }
        connection?.connect()
        clockJob =
            viewModelScope.launch {
                delay(6_000)
                if (version == generation &&
                    !mutable.value.connected
                ) {
                    connectionClosed(version, "Host did not finish the connection handshake.")
                }
            }
    }

    private suspend fun sendHandshake(
        invite: PairingInvitation?,
        profile: HostProfile?,
        version: Int,
    ) {
        val frame = handshake.frame(invite, profile)
        if (version != generation) return
        frame.put("request_id", id())
        connection?.send(frame)
    }

    private fun connectionClosed(
        version: Int,
        message: String,
    ) {
        if (version != generation) return
        reportLog("warning", "connection.closed", message)
        activeEndpoint?.let { endpoints.failed(it, SystemClock.elapsedRealtime()) }
        disconnect()
        mutable.update {
            it.copy(
                connected = false,
                connecting = false,
                connectionIssue = message,
                searching = false,
                preparing = false,
                lyricsLoading = false,
            )
        }
        clockJob?.cancel()
        if (invitation != null) {
            showError("Could not pair", message)
            return
        }
        if (maintainBackgroundSessionInternal() && mutable.value.profile != null) {
            startDiscovery()
            reconnect?.cancel()
            reconnect =
                viewModelScope.launch {
                    delay(retryDelay)
                    retryDelay = (retryDelay * 2).coerceAtMost(30_000)
                    connect()
                }
        }
    }

    fun disconnect() {
        generation++
        frameQueue.clear()
        receiveJob?.cancel()
        reconnect?.cancel()
        clockJob?.cancel()
        connection?.disconnect()
        connection = null
        clock.reset()
        searchTimeout?.cancel()
        preparationTimeout?.cancel()
        lyricsTimeout?.cancel()
        lyricRequestId = null
        lyricUserInitiated = false
        clearArtworkRequests()
        mutable.update {
            it.copy(
                connected = false,
                connecting = false,
                searching = false,
                preparing = false,
                lyricsLoading = false,
            )
        }
    }

    private suspend fun receive(frame: JSONObject) {
        lastReceivedAt = SystemClock.elapsedRealtime()
        when (frame.getString("type")) {
            "session.status" -> applySessionStatus(frame.getJSONObject("status"))
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
            "search.result" ->
                if (frame.nullableString("request_id") == searchId) {
                    searchTimeout?.cancel()
                    val songs = frame.getJSONArray("songs").objects().map(Wire::song)
                    mutable.update { it.copy(results = songs, searching = false) }
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
                    lyricUserInitiated = false
                    lyricsTimeout?.cancel()
                    mutable.update {
                        it.copy(
                            lyricsLoading = false,
                            lyricsIssue = frame.optString("message", "Lyrics are unavailable."),
                        )
                    }
                }
            "command.result" -> commandResult(frame)
            "error" -> operationErrorInternal(frame)
            "operation.started" -> Unit
            else -> Unit
        }
    }

    private suspend fun welcome(value: JSONObject) {
        require(value.getInt("protocol_major") == 1) { "Update Host and Remote to compatible versions." }
        val invite = invitation
        val previous = mutable.value.profile
        val profile =
            HostProfile(
                value.getString("host_id"),
                value.getString("host_name"),
                activeEndpoint?.address ?: invite?.host ?: requireNotNull(previous).address,
                activeEndpoint?.port ?: invite?.port ?: requireNotNull(previous).port,
                invite?.fingerprint ?: requireNotNull(previous).fingerprint,
                value.getString("remote_id"),
                invite?.certificateDerBase64 ?: requireNotNull(previous).certificateDerBase64,
            )
        val token = value.nullableString("token")
        withContext(ioDispatcher) {
            if (token != null) app.vault.save("host." + profile.hostId, token)
            app.database.saveProfile(profile)
            preferences.write("active_host" to profile.hostId, "client_name" to remoteName)
        }
        invitation = null
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
        flushLogOutbox()
        publishStatus()
        if ("remote.configure" in mutable.value.capabilities) {
            connection?.send(
                Wire
                    .frame("remote.configure")
                    .put("request_id", id())
                    .put("name", remoteName)
                    .put("heartbeat", true),
            )
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
            if (!pending.containsKey(commandId)) {
                pending[commandId] = PendingCommand(frame, key, Job().apply { complete() })
                mutable.update { it.copy(pending = it.pending + key) }
            }
            queryRequest(commandId)
        }
    }

    private suspend fun applyState(value: JSONObject) {
        val snapshot = enrichArtwork(Wire.snapshot(value))
        require(snapshot.hostId == mutable.value.profile?.hostId) { "Host identity did not match this pairing." }
        val previous = mutable.value.snapshot
        if (previous?.hostEpoch == snapshot.hostEpoch && snapshot.sequence <= previous.sequence) return
        if (previous != null && previous.hostEpoch != snapshot.hostEpoch) clock.reset()
        val changedSong = snapshot.current?.occurrenceId != previous?.current?.occurrenceId
        if (changedSong || previous?.revision != snapshot.revision || SystemClock.elapsedRealtime() - lastCachedAt >= 5_000) {
            withContext(ioDispatcher) { app.database.saveState(snapshot.hostId, value) }
            lastCachedAt = SystemClock.elapsedRealtime()
        }
        mutable.update {
            it.copy(
                snapshot = snapshot,
                lastStateAt = SystemClock.elapsedRealtime(),
                lyrics = if (changedSong) null else it.lyrics,
                lyricsIssue = if (changedSong) null else it.lyricsIssue,
                lyricsLoading = if (changedSong) false else it.lyricsLoading,
            )
        }
        if (!foreground && !mutable.value.monitoringSong && !snapshot.playing) {
            endSessionStatus()
        }
        val songs = snapshot.queue.map { it.song } + listOfNotNull(snapshot.current?.song)
        val new = songs.filter { metadata.add(it.source + ":" + it.id) }
        if (new.isNotEmpty()) withContext(ioDispatcher) { app.database.remember(snapshot.hostId, new) }
    }

    private fun enrichArtwork(snapshot: HostSnapshot): HostSnapshot {
        val known =
            (
                mutable.value.favorites + mutable.value.results +
                    listOfNotNull(
                        mutable.value.snapshot
                            ?.current
                            ?.song,
                    ) +
                    mutable.value.snapshot
                        ?.queue
                        .orEmpty()
                        .map { it.song }
            ).filter { it.artworkUrl != null }
                .associateBy { it.source + ":" + it.id }

        fun song(value: Song): Song = value.artworkUrl?.let { value } ?: known[value.source + ":" + value.id] ?: value
        return snapshot.copy(
            current = snapshot.current?.copy(song = song(snapshot.current.song)),
            queue = snapshot.queue.map { it.copy(song = song(it.song)) },
            incoming = snapshot.incoming?.let(::song),
        )
    }

    private suspend fun applyCredit(frame: JSONObject) {
        val host = mutable.value.profile?.hostId ?: return
        val cursor =
            withContext(ioDispatcher) {
                frame.optJSONObject("song_metadata")?.let { app.database.remember(host, listOf(Wire.song(it))) }
                app.database.applyCredit(host, frame)
            }
        connection?.send(Wire.frame("analytics.ack").put("sequence", cursor))
        reloadStatistics()
    }

    private fun pingClock() {
        lastClockSentAt = SystemClock.elapsedRealtime()
        connection?.send(
            Wire
                .frame("clock")
                .put("request_id", id())
                .put("clock", JSONObject().put("sent_at_remote_ms", SystemClock.elapsedRealtime())),
        )
    }

    fun search(
        query: String,
        library: Boolean,
    ) {
        if (!mutable.value.connected) return showError("Connect to Host", "Reconnect before searching.")
        searchId?.let { connection?.send(Wire.frame("operation.cancel").put("request_id", it)) }
        searchId = id()
        val requestId = searchId
        searchTimeout?.cancel()
        mutable.update { it.copy(searching = true) }
        connection?.send(
            Wire
                .frame(
                    "search",
                ).put("request_id", searchId)
                .put("query", query.take(200))
                .put("scope", if (library) "library" else "catalog"),
        )
        searchTimeout =
            viewModelScope.launch {
                delay(15_000)
                if (requestId == searchId && mutable.value.searching) {
                    mutable.update {
                        it.copy(searching = false, notice = Notice("Search timed out. Try again."))
                    }
                }
            }
    }

    fun prepare(song: Song) {
        preparationId = id()
        val requestId = preparationId
        preparationTimeout?.cancel()
        mutable.update { it.copy(preparing = true, preparedSong = null) }
        connection?.send(Wire.frame("song.prepare").put("request_id", preparationId).put("song", song.identity.json()))
        preparationTimeout =
            viewModelScope.launch {
                delay(15_000)
                if (requestId == preparationId && mutable.value.preparing) {
                    mutable.update {
                        it.copy(preparing = false, notice = Notice("Music did not prepare this song. Try again."))
                    }
                }
            }
    }

    fun loadLyrics(userInitiated: Boolean = true) {
        if (mutable.value.lyricsLoading) return
        if (!mutable.value.connected) return showError("Connect to Host", "Reconnect before loading lyrics.")
        lyricRequestId = id()
        val requestId = lyricRequestId
        lyricsTimeout?.cancel()
        lyricUserInitiated = userInitiated
        mutable.update { it.copy(lyricsLoading = true) }
        connection?.send(Wire.frame("lyrics.get").put("request_id", lyricRequestId))
        lyricsTimeout =
            viewModelScope.launch {
                delay(15_000)
                if (requestId == lyricRequestId && mutable.value.lyricsLoading) {
                    lyricUserInitiated = false
                    mutable.update {
                        it.copy(lyricsLoading = false, lyricsIssue = "Host did not return lyrics. Try again.")
                    }
                }
            }
    }

    fun savePreferences(
        name: String,
        theme: ThemePreference,
    ) {
        if (mutable.value.savingPreferences) return
        val clean = name.trim()
        if (clean.length !in 1..80 || clean.any { it.isISOControl() }) {
            showError("Check the Remote name", "Use 1 to 80 characters without control characters.")
            return
        }
        mutable.update { it.copy(savingPreferences = true) }
        viewModelScope.launch {
            try {
                withContext(ioDispatcher) { preferences.write("client_name" to clean, "theme" to theme.name) }
                val renamed = remoteName != clean
                remoteName = clean
                mutable.update { it.copy(clientName = clean, theme = theme, notice = Notice("Preferences saved")) }
                if (renamed && mutable.value.connected) connect()
            } catch (error: Exception) {
                showError("Could not save preferences", error.message ?: "Your previous settings were preserved.")
            } finally {
                mutable.update { it.copy(savingPreferences = false) }
            }
        }
    }

    fun toggleFavorite(song: Song) {
        if (mutable.value.savingFavorite) return
        val saved = mutable.value.favorites.none { it.identity == song.identity }
        mutable.update { it.copy(savingFavorite = true) }
        viewModelScope.launch {
            try {
                val library =
                    withContext(ioDispatcher) {
                        app.library.setFavorite(song, saved)
                        app.library.load()
                    }
                mutable.update {
                    it.copy(
                        favorites = library.songs,
                        unreadableFavorites = library.unreadable,
                        notice = Notice(if (saved) "Saved to Favorites" else "Removed from Favorites"),
                    )
                }
            } catch (error: Exception) {
                showError("Could not update Favorites", error.message ?: "Your saved songs were preserved.")
            } finally {
                mutable.update { it.copy(savingFavorite = false) }
            }
        }
    }

    fun command(
        action: JSONObject,
        key: String,
    ) {
        mutable.update { it.copy(sessionActive = true) }
        viewModelScope.launch { sendCommand(action, key) }
    }

    private suspend fun sendCommand(
        action: JSONObject,
        key: String,
    ) {
        var createdId: String? = null
        var createdProfile: HostProfile? = null
        var sent = false
        try {
            val session = generation
            val transport = requireNotNull(connection) { "Reconnect before sending this request." }
            val profile = requireNotNull(mutable.value.profile)
            createdProfile = profile
            val snapshot = requireNotNull(mutable.value.snapshot) { "Wait for Host state." }
            check(mutable.value.connected && !isStale()) { "Reconnect and wait for current Host state." }
            check(key !in mutable.value.pending && pending.values.none { it.key == key }) {
                "This request is still pending. Check its original outcome before retrying."
            }
            val command =
                Wire
                    .frame("command")
                    .put("command_id", id())
                    .put("host_epoch", snapshot.hostEpoch)
                    .put("expires_at_host_ms", clock.deadline(SystemClock.elapsedRealtime()))
                    .put("expected_revision", snapshot.revision)
                    .put("action", action)
            val commandId = command.getString("command_id")
            createdId = commandId
            check(pending.size < 32) { "Resolve earlier unconfirmed requests before sending more." }
            mutable.update { it.copy(pending = it.pending + key) }
            val timer =
                viewModelScope.launch {
                    delay(1_000)
                    if (session == generation && foreground && pending.containsKey(commandId)) {
                        mutable.update {
                            it.copy(
                                pending = it.pending - key,
                                prompt =
                                    Prompt(
                                        "Request unconfirmed",
                                        "Host did not confirm this request within one second. Check the original request before retrying.",
                                        commandId,
                                    ),
                            )
                        }
                        queryRequest(commandId)
                        connection?.send(Wire.frame("state.get").put("request_id", id()))
                    }
                }
            pending[commandId] = PendingCommand(command, key, timer)
            withContext(ioDispatcher) { app.database.savePending(profile, command, key) }
            check(
                session == generation && transport === connection && mutable.value.profile == profile &&
                    (foreground || key.startsWith("playback.")) && mutable.value.connected,
            ) {
                "The connection changed while saving this request. Review the current queue before retrying."
            }
            check(
                clock.hostTime(SystemClock.elapsedRealtime()) < command.counter("expires_at_host_ms"),
            ) { "This request expired before it was sent." }
            pending[commandId]?.sentAtElapsedMs = SystemClock.elapsedRealtime()
            sent = transport.send(command)
            check(sent) { "The connection closed before the request was sent." }
        } catch (error: Exception) {
            if (!sent && createdId != null) {
                pending.remove(createdId)?.timer?.cancel()
                mutable.update { it.copy(pending = pending.values.map { item -> item.key }.toSet()) }
                val profile = createdProfile
                val failedId = createdId
                if (profile != null) withContext(ioDispatcher) { app.database.finishPending(profile, failedId) }
            }
            showError("Action unavailable", error.message ?: "Reconnect and retry.")
        }
    }

    private suspend fun commandResult(frame: JSONObject) {
        val commandId = frame.getString("command_id")
        val original = pending[commandId] ?: return
        if (frame.nullableString("host_epoch") != mutable.value.snapshot?.hostEpoch) return
        original.timer.cancel()
        val sentAt = original.sentAtElapsedMs
        if (sentAt > 0) {
            mutable.update { it.copy(lastCommandLatencyMs = (SystemClock.elapsedRealtime() - sentAt).coerceAtLeast(0)) }
        }
        when (frame.getString("outcome")) {
            "applied" -> {
                statusChecks.remove(commandId)
                val profile = mutable.value.profile
                if (profile != null) withContext(ioDispatcher) { app.database.finishPending(profile, commandId) }
                pending.remove(commandId)
                mutable.update { it.copy(pending = it.pending - original.key, notice = Notice("Request applied")) }
            }
            "unconfirmed" -> {
                val showPrompt = statusChecks.remove(commandId)
                val resolved = frame.optBoolean("resolved", false)
                if (resolved) {
                    val profile = mutable.value.profile
                    if (profile != null) withContext(ioDispatcher) { app.database.finishPending(profile, commandId) }
                    pending.remove(commandId)
                    mutable.update { it.copy(pending = it.pending - original.key) }
                }
                mutable.update {
                    if (showPrompt) {
                        it.copy(
                            prompt =
                                Prompt(
                                    "Request unconfirmed",
                                    frame.optString("message", "Check this request after Host reconciles Music."),
                                    if (resolved) null else commandId,
                                ),
                        )
                    } else {
                        it.copy(notice = Notice("Request still needs confirmation"))
                    }
                }
            }
            else -> {
                statusChecks.remove(commandId)
                val profile = mutable.value.profile
                if (profile != null) withContext(ioDispatcher) { app.database.finishPending(profile, commandId) }
                pending.remove(commandId)
                mutable.update { it.copy(pending = it.pending - original.key) }
                showError("Request blocked", frame.optString("message", "The queue changed or Host settings protect this request."))
            }
        }
    }

    override fun onCleared() {
        SessionNotification(app).clear()
        app.unpinSession = null
        app.mediaAction = null
        mediaSession.release()
        networkMonitor.close()
        disconnect()
        discovery?.close()
        for (item in pending.values) item.timer.cancel()
        frameQueue.clear()
        frameSignal.close()
    }

    fun beginPairing() = beginPairingInternal()
}
