package app.cadenza.remote.model

import app.cadenza.remote.data.EffectiveTransportDecision
import app.cadenza.remote.data.HostProfile
import app.cadenza.remote.data.HostSnapshot
import app.cadenza.remote.data.LyricDocument
import app.cadenza.remote.data.Song
import app.cadenza.remote.data.SongStatistic
import app.cadenza.remote.data.ThemePreference
import app.cadenza.remote.data.TransportPathStatus
import app.cadenza.remote.data.UpdateConfiguration
import java.util.UUID

data class RecommendationItem(
    val recommendationId: String,
    val planId: String,
    val source: String,
    val songId: String,
    val title: String? = null,
    val artist: String? = null,
    val confidence: Double,
    val evidence: List<String>,
    val expiresAtMs: Long,
)

data class Prompt(
    val title: String,
    val message: String,
    val commandId: String? = null,
    val id: String = UUID.randomUUID().toString(),
)

data class Notice(
    val message: String,
    val id: String = UUID.randomUUID().toString(),
)

data class DebugLogEntry(
    val timestampMs: Long,
    val title: String,
    val message: String,
)

data class RemoteState(
    val loaded: Boolean = false,
    val clientName: String = "Android Remote",
    val theme: ThemePreference = ThemePreference.SYSTEM,
    val favorites: List<Song> = emptyList(),
    val capabilities: Set<String> = emptySet(),
    val sessionActive: Boolean = false,
    val hostUpdate: HostUpdateStatus? = null,
    val unreadableFavorites: Int = 0,
    val savingPreferences: Boolean = false,
    val savingFavorite: Boolean = false,
    val profile: HostProfile? = null,
    val connected: Boolean = false,
    val connecting: Boolean = false,
    val effectiveTransport: EffectiveTransportDecision? = null,
    val transportPaths: List<TransportPathStatus> = emptyList(),
    val transportPreference: String = "balanced",
    val transportMode: String = "lan",
    val connectionIssue: String? = null,
    val snapshot: HostSnapshot? = null,
    val artwork: Map<String, ByteArray> = emptyMap(),
    val lastStateAt: Long = 0,
    val lyrics: LyricDocument? = null,
    val lyricsLoading: Boolean = false,
    val lyricsIssue: String? = null,
    val results: List<Song> = emptyList(),
    val searching: Boolean = false,
    val preparing: Boolean = false,
    val preparedSong: String? = null,
    val pending: Set<String> = emptySet(),
    val lastCommandLatencyMs: Long? = null,
    val clockUncertaintyMs: Long? = null,
    val statistics: List<SongStatistic> = emptyList(),
    val prompt: Prompt? = null,
    val notice: Notice? = null,
    val updateConfiguration: UpdateConfiguration = UpdateConfiguration(),
    val updateStatus: String = "",
    val updateBusy: Boolean = false,
    val installationBusy: Boolean = false,
    val stagedUpdate: String? = null,
    val changelog: String? = null,
    val comparingChanges: Boolean = false,
    val debugLog: List<DebugLogEntry> = emptyList(),
    val creeMode: String = "disabled",
    val nextRecommendation: RecommendationItem? = null,
)
