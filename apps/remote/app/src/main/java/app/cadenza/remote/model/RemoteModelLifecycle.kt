package app.cadenza.remote.model

import android.os.SystemClock
import kotlinx.coroutines.flow.update
import java.util.UUID

internal fun RemoteModel.id(): String = UUID.randomUUID().toString()

fun RemoteModel.isStale(now: Long = SystemClock.elapsedRealtime()): Boolean = isStaleInternal(now)

fun RemoteModel.position(now: Long): Long = positionInternal(now)

fun RemoteModel.endSessionStatus() = endSessionStatusInternal()

internal fun RemoteModel.beginPairingInternal() {
    disconnect()
    discovery?.close()
    discovery = null
    for (item in pending.values) item.timer.cancel()
    pending.clear()
    hostSnapshot = null
    invitation = null
    mutable.update { it.copy(profile = null, snapshot = null, lyrics = null, results = emptyList()) }
}
