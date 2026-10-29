package app.cadenza.remote

import android.os.SystemClock
import kotlinx.coroutines.flow.update
import java.util.UUID

internal fun RemoteModel.id(): String = UUID.randomUUID().toString()

fun RemoteModel.checkRequest(commandId: String) = checkRequestInternal(commandId)

fun RemoteModel.isStale(now: Long = SystemClock.elapsedRealtime()): Boolean = isStaleInternal(now)

fun RemoteModel.position(now: Long): Long = positionInternal(now)

fun RemoteModel.monitorSong() = monitorSongInternal()

fun RemoteModel.endSessionStatus() = endSessionStatusInternal()

internal fun RemoteModel.beginPairingInternal() {
    disconnect()
    discovery?.close()
    discovery = null
    for (item in pending.values) item.timer.cancel()
    pending.clear()
    statusChecks.clear()
    invitation = null
    mutable.update { it.copy(profile = null, snapshot = null, lyrics = null, results = emptyList(), pending = emptySet()) }
}
