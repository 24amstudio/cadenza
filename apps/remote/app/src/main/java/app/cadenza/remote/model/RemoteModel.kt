package app.cadenza.remote.model

import android.app.Application
import android.os.SystemClock
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.cadenza.remote.BuildConfig
import app.cadenza.remote.CadenzaApplication
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
import app.cadenza.remote.media.RemoteMediaActions
import app.cadenza.remote.media.RemoteMediaSession
import app.cadenza.remote.media.SessionNotification
import app.cadenza.remote.media.SessionStatus
import app.cadenza.remote.motion.MotionAssembly
import app.cadenza.remote.motion.MotionStore
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
import app.cadenza.remote.network.loadPairingCertificate
import app.cadenza.remote.network.parsePairingInvitation
import app.cadenza.remote.recommendation.RecommendationEngine
import app.cadenza.remote.recommendation.RecommendationFeedback
import app.cadenza.remote.recommendation.RecommendationOutcome
import app.cadenza.remote.recommendation.RecommendationPassportSigner
import app.cadenza.remote.recommendation.RecommendationTrack
import app.cadenza.remote.recommendation.newRecommendationId
import app.cadenza.remote.search.SearchHistory
import app.cadenza.remote.search.correctionFor
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
import java.io.File
import java.util.UUID

private const val SUGGEST_DELAY_MS = 180L

class RemoteModel(
    application: Application,
    internal val ioDispatcher: CoroutineDispatcher,
) : AndroidViewModel(application) {
    constructor(application: Application) : this(application, Dispatchers.IO)

    internal val app = application as CadenzaApplication

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

    internal var generation = 0

    internal var foreground = false

    private var receiveJob: Job? = null

    internal var invitation: PairingInvitation? = null

    internal var pairingPin: String? = null

    internal var remoteName = deviceName(application)

    internal var reconnect: Job? = null

    internal var clockJob: Job? = null

    internal var lastReceivedAt = 0L

    internal var lastHeartbeatAt = 0L

    internal var lastClockSentAt = 0L

    internal var lastStatusSentAt = 0L

    internal var retryDelay = 1_000L

    internal var searchId: String? = null

    internal var correctionId: String? = null

    internal var searchedQuery = ""

    internal var searchedScope = "catalog"

    internal var motionRequestId: String? = null

    internal var motionAssembly: MotionAssembly? = null

    internal val motionStore by lazy { MotionStore(File(app.filesDir, "motion")) }

    internal var preparationId: String? = null

    internal var searchTimeout: Job? = null

    internal var preparationTimeout: Job? = null

    internal var lyricsTimeout: Job? = null

    internal var lyricRequestId: String? = null

    internal var lyricUserInitiated = false

    internal var discovery: HostDiscovery? = null

    private var lastDiscoveredAt = 0L

    internal val endpoints = EndpointPool()

    internal val statusPublisher = RemoteStatusPublisher(app)

    internal val pathMeasurements = PathMeasurementService()

    internal val handshake = RemoteHandshake(app, ioDispatcher) { remoteName }

    internal var activeEndpoint: LocalEndpoint? = null

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

    internal var lastCachedAt = 0L

    internal var logFlush: Job? = null

    internal var suggestJob: Job? = null
    internal var suggestionId: String? = null

    internal val pending = mutableMapOf<String, PendingCommand>()

    // The Host's last snapshot. The published snapshot is this one with unanswered command intents applied.
    internal var hostSnapshot: HostSnapshot? = null

    internal val frameQueue = PrioritizedFrameQueue()

    // State frames are coalesced by PrioritizedFrameQueue. A conflated wakeup
    // avoids retaining one signal per network frame during transport bursts.
    internal val frameSignal = Channel<Unit>(Channel.CONFLATED)

    internal val metadata = mutableSetOf<String>()

    internal val artworkRequests = mutableSetOf<String>()

    internal val mutableState get() = mutable

    internal val updateApp get() = app

    internal val updateDispatcher get() = ioDispatcher

    internal val updateScope get() = viewModelScope

    internal val recommendationEngine by lazy {
        RecommendationEngine(RecommendationPassportSigner(application.packageName + ".recommendation"))
    }

    init {
        app.mediaAction = mediaActions::handle
        viewModelScope.launch {
            state.map(SessionStatus::from).distinctUntilChanged().collect { SessionNotification(app).update(it, mediaToken) }
        }
        viewModelScope.launch {
            state.map(mediaActions::sessionState).distinctUntilChanged().collect(mediaSession::update)
        }
        viewModelScope.launch {
            for (ignored in frameSignal) {
                while (true) {
                    val item = frameQueue.poll() ?: break
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
                hostSnapshot = cached
                mutable.update {
                    it.copy(
                        loaded = true,
                        clientName = remoteName,
                        transportMode = preferences.getString("transport_mode", "lan") ?: "lan",
                        recentSearches = SearchHistory.decode(preferences.getString("recent_searches", null)),
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

    internal fun startDiscovery() {
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
            val invite = parsePairingInvitation(payload, name)
            val firstPairing = mutable.value.profile == null
            invitation = invite
            pairingPin = null
            endpoints.clear()
            remoteName = name.trim()
            if (firstPairing) {
                // A QR pairing establishes the certificate used by both LAN and
                // BLE. Start the first session in hybrid mode so the Remote can
                // discover the Host's BLE peripheral immediately after pairing.
                transportMode = "hybrid"
                preferences.write("transport_mode" to transportMode)
                mutable.update { it.copy(transportMode = transportMode) }
            }
            if (invite.certificateDerBase64.isEmpty()) {
                mutable.update { it.copy(connecting = true, connectionIssue = null) }
                viewModelScope.loadPairingCertificate(invite, ioDispatcher) { result ->
                    result
                        .onSuccess { certificate ->
                            if (invitation == invite) {
                                invitation = invite.copy(certificateDerBase64 = certificate)
                                connect()
                            }
                        }.onFailure { error ->
                            if (invitation == invite) {
                                invitation = null
                                val message = error.message ?: "Could not retrieve the Host certificate."
                                mutable.update { it.copy(connecting = false, connectionIssue = message) }
                                showError("Could not connect", message)
                            }
                        }
                }
            } else {
                connect()
            }
        } catch (error: Exception) {
            val message = error.message ?: "Scan a current Host QR code."
            mutable.update { it.copy(connecting = false, connectionIssue = message) }
            showError("Could not scan QR", message)
        }
    }

    fun connect() {
        try {
            openConnection()
        } catch (error: Exception) {
            disconnect()
            val message = error.message ?: "Check pairing details and reconnect."
            mutable.update { it.copy(connectionIssue = message) }
            showError("Could not connect", message)
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

    fun reconnectWithTransport(mode: String) {
        require(mode in setOf("lan", "ble", "hybrid")) { "Unsupported transport mode." }
        if (transportMode != mode) {
            transportMode = mode
            preferences.write("transport_mode" to mode)
            mutable.update { it.copy(transportMode = mode) }
        }
        connect()
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
                effectiveTransport = null,
                transportPaths = emptyList(),
                searching = false,
                preparing = false,
                lyricsLoading = false,
            )
        }
    }

    fun search(
        query: String,
        library: Boolean,
    ) {
        if (!mutable.value.connected) return showError("Connect to Host", "Reconnect before searching.")
        reportLog("info", "search.requested", "scope=${if (library) "library" else "catalog"} chars=${query.length}")
        val recent = SearchHistory.add(mutable.value.recentSearches, query)
        mutable.update { it.copy(recentSearches = recent, correctedQuery = null, correctedResults = emptyList()) }
        viewModelScope.launch(ioDispatcher) { preferences.write("recent_searches" to SearchHistory.encode(recent)) }
        searchId?.let { connection?.send(Wire.frame("operation.cancel").put("request_id", it)) }
        correctionId?.let { connection?.send(Wire.frame("operation.cancel").put("request_id", it)) }
        correctionId = null
        searchId = id()
        searchedQuery = query.take(200)
        searchedScope = if (library) "library" else "catalog"
        val requestId = searchId
        searchTimeout?.cancel()
        mutable.update { it.copy(searching = true) }
        connection?.send(
            Wire
                .frame(
                    "search",
                ).put("request_id", searchId)
                .put("query", searchedQuery)
                .put("scope", searchedScope),
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

    // A search that finds no real match is retried with the known title it most likely meant, so the user sees both
    // without first tapping a suggestion.
    internal fun correctIfNeeded(songs: List<Song>) {
        val correction = correctionFor(searchedQuery, songs, knownTerms()) ?: return
        correctionId = id()
        mutable.update { it.copy(correctedQuery = correction) }
        connection?.send(
            Wire
                .frame("search")
                .put("request_id", correctionId)
                .put("query", correction.take(200))
                .put("scope", searchedScope),
        )
    }

    private fun knownTerms(): List<String> {
        val state = mutable.value
        return state.recentSearches + state.favorites.map { it.title } + state.statistics.map { it.title } + state.suggestedTerms
    }

    // Asks the Host for Apple's completions once typing pauses. Earlier answers are ignored by request identifier, so a
    // slow reply cannot replace the suggestions for what the user typed last.
    fun suggest(query: String) {
        val text = query.trim().take(200)
        suggestJob?.cancel()
        if (text.isEmpty() || !mutable.value.connected || "search.suggest" !in mutable.value.capabilities) return
        suggestJob =
            viewModelScope.launch {
                delay(SUGGEST_DELAY_MS)
                suggestionId = id()
                connection?.send(Wire.frame("search.suggest").put("request_id", suggestionId).put("query", text))
            }
    }

    fun prepare(song: Song) {
        reportLog("info", "prepare.requested", "song=${song.source}:${song.id}")
        preparationId = id()
        val requestId = preparationId
        preparationTimeout?.cancel()
        mutable.update { it.copy(preparing = true, preparedSong = null) }
        connection?.send(
            Wire
                .frame("song.prepare")
                .put("request_id", preparationId)
                .put("song", song.identity.json())
                .put(
                    "song_metadata",
                    JSONObject()
                        .put("source", song.source)
                        .put("id", song.id)
                        .put("title", song.title)
                        .put("artist", song.artist)
                        .put("album", song.album)
                        .put("duration_ms", song.durationMs ?: JSONObject.NULL)
                        .put("artwork_url", song.artworkUrl ?: JSONObject.NULL),
                ),
        )
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
        reportLog("info", "lyrics.requested", "user=$userInitiated")
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
        val feedback = favoriteRecommendationFeedback(song, saved)
        recommendationEngine.recordFeedback(feedback)
        sendRecommendationFeedback(feedback)
        reportLog("info", "favorite.requested", "song=${song.source}:${song.id} saved=$saved")
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
        song: Song? = null,
    ) {
        recordRecommendationCommand(action)
        mutable.update { it.copy(sessionActive = true) }
        viewModelScope.launch { sendCommand(action, key, song) }
    }

    override fun onCleared() {
        SessionNotification(app).clear()
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
