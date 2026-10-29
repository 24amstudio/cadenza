package app.cadenza.remote

import app.cadenza.remote.data.HostProfile
import app.cadenza.remote.data.PairingInvitation
import app.cadenza.remote.data.Wire
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext
import org.json.JSONObject

class RemoteHandshake(
    private val app: CadenzaApplication,
    private val dispatcher: CoroutineDispatcher,
    private val name: () -> String,
) {
    suspend fun frame(
        invite: PairingInvitation?,
        profile: HostProfile?,
    ): JSONObject =
        if (invite != null) {
            Wire.frame("pair").put(
                "pair",
                JSONObject()
                    .put("name", name())
                    .put("secret", invite.secret)
                    .put("remote_version", BuildConfig.VERSION_NAME),
            )
        } else {
            val stored = requireNotNull(profile)
            val credentials =
                withContext(dispatcher) {
                    val token =
                        requireNotNull(app.vault.read("host." + stored.hostId)) {
                            "Pairing credentials are unavailable. Pair again."
                        }
                    JSONObject()
                        .put("remote_id", stored.remoteId)
                        .put("token", token)
                        .put("last_credit_sequence", app.database.cursor(stored.hostId))
                        .put("remote_version", BuildConfig.VERSION_NAME)
                }
            Wire.frame("hello").put("auth", credentials)
        }
}
