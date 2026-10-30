package app.cadenza.remote.network

import app.cadenza.remote.data.PairingInvitation
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

internal fun CoroutineScope.loadPairingCertificate(
    invitation: PairingInvitation,
    dispatcher: CoroutineDispatcher,
    onResult: (Result<String>) -> Unit,
): Job =
    launch {
        try {
            onResult(
                Result.success(
                    withContext(dispatcher) {
                        HostCertificateBootstrap.fetch(invitation.host, invitation.port, invitation.secret)
                    },
                ),
            )
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            onResult(Result.failure(error))
        }
    }
