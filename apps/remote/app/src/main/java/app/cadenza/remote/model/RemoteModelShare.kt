package app.cadenza.remote.model

import app.cadenza.remote.data.SongIdentity
import kotlinx.coroutines.flow.update

/** Holds a song shared from Apple Music until the person chooses Play now, Play next, Add to queue, or Cancel. */
fun RemoteModel.receiveSharedTrack(identity: SongIdentity?) {
    mutableState.update { it.copy(sharedTrack = identity) }
}
