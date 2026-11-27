package app.cadenza.remote.model

import app.cadenza.remote.data.EffectiveTransportDecision
import app.cadenza.remote.data.HostProfile
import app.cadenza.remote.data.HostSnapshot
import app.cadenza.remote.data.LyricDocument
import app.cadenza.remote.data.LyricsTextSize
import app.cadenza.remote.data.Song
import app.cadenza.remote.data.SongIdentity
import app.cadenza.remote.data.SongStatistic
import app.cadenza.remote.data.ThemePreference
import app.cadenza.remote.data.TransportPathStatus
import app.cadenza.remote.data.UpdateConfiguration
import app.cadenza.remote.updates.HostLanUpdate
import java.io.File
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

data class MotionVideo(
    val occurrenceId: String,
    val file: File,
)

// An artist's motion video for the Artist Details header. The file is verified before it is published.
data class ArtistMotionVideo(
    val artistName: String,
    val file: File,
)

data class RemoteState(
    val loaded: Boolean = false,
    val clientName: String = "Android Remote",
    val theme: ThemePreference = ThemePreference.SYSTEM,
    val lyricsTextSize: LyricsTextSize = LyricsTextSize.LARGE,
    val favorites: List<Song> = emptyList(),
    val capabilities: Set<String> = emptySet(),
    // The Host's version name and build, from its welcome. Null until a Host that reports them has welcomed this Remote.
    val hostVersion: String? = null,
    val hostBuild: Long? = null,
    // The Remote build the Host offers over the LAN, from the welcome. Null when the Host offers nothing.
    val hostOffer: HostLanUpdate.Offer? = null,
    // Set when the Host has been silent for several minutes. Its playback is then assumed interrupted.
    val sessionInterrupted: Boolean = false,
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
    val songChangeNotifications: Boolean = true,
    val tasteDigestOptIn: Boolean = false,
    val volumeRockerControl: Boolean = false,
    val lockScreenMotionArtwork: Boolean = true,
    val silentPlaybackKeepAlive: Boolean = true,
    val transportMode: String = "lan",
    val connectionIssue: String? = null,
    val snapshot: HostSnapshot? = null,
    val artwork: Map<String, ByteArray> = emptyMap(),
    val lastStateAt: Long = 0,
    val lyrics: LyricDocument? = null,
    // The karaoke nudge in use, in milliseconds. Lyrics are matched against the position minus this.
    val lyricDelayMs: Int = 0,
    val lyricsLoading: Boolean = false,
    val lyricsIssue: String? = null,
    val results: List<Song> = emptyList(),
    val recentSearches: List<String> = emptyList(),
    val suggestedTerms: List<String> = emptyList(),
    val suggestedSongs: List<Song> = emptyList(),
    val correctedQuery: String? = null,
    val correctedResults: List<Song> = emptyList(),
    val motion: MotionVideo? = null,
    val artistMotion: ArtistMotionVideo? = null,
    val searching: Boolean = false,
    val preparing: Boolean = false,
    val preparedSong: String? = null,
    val lastCommandLatencyMs: Long? = null,
    val clockUncertaintyMs: Long? = null,
    val linkRoundTripMs: Long? = null,
    val statistics: List<SongStatistic> = emptyList(),
    val prompt: Prompt? = null,
    val notice: Notice? = null,
    val autoPlayRequest: AutoPlayRequest? = null,
    val updateConfiguration: UpdateConfiguration = UpdateConfiguration(),
    val updateStatus: String = "",
    val updateBusy: Boolean = false,
    val installationBusy: Boolean = false,
    val stagedUpdate: String? = null,
    val changelog: String? = null,
    val comparingChanges: Boolean = false,
    // A song shared from Apple Music, waiting for the person to choose what the Host does with it.
    val sharedTrack: SongIdentity? = null,
    val debugLog: List<DebugLogEntry> = emptyList(),
    val creeMode: String = "disabled",
    val nextRecommendation: RecommendationItem? = null,
    val browse: Map<String, BrowseLoad> = emptyMap(),
)
