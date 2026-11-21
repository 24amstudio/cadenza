package app.cadenza.remote.model

import app.cadenza.remote.BuildConfig
import kotlinx.coroutines.flow.update

// Which of two builds is older. Both sides take their build numbers from the same release counter, so comparing them
// says which side needs the update, whatever version name either side shows.
internal enum class VersionGap { Unknown, Same, RemoteOlder, RemoteNewer }

internal fun versionGap(
    remoteBuild: Long,
    hostBuild: Long?,
): VersionGap =
    when {
        hostBuild == null -> VersionGap.Unknown
        remoteBuild < hostBuild -> VersionGap.RemoteOlder
        remoteBuild > hostBuild -> VersionGap.RemoteNewer
        else -> VersionGap.Same
    }

// Runs after each welcome. An older Host is updated from here, but an install restarts it, so it waits until the Host is
// idle, and only a few automatic installs are tried. An older Remote is asked to update, because Android installs a new
// Remote only with the person's approval.
internal fun RemoteModel.reconcileVersions() {
    val state = mutableState.value
    when (versionGap(BuildConfig.VERSION_CODE.toLong(), state.hostBuild)) {
        VersionGap.RemoteNewer ->
            if (state.snapshot?.playing != true && hostUpdateInstalls < MAXIMUM_AUTOMATIC_HOST_UPDATES) {
                hostUpdateCheckedAutomatically = true
                checkHostUpdate()
            }
        VersionGap.RemoteOlder -> {
            val host = state.hostVersion ?: "a newer version"
            mutableState.update {
                it.copy(
                    prompt =
                        Prompt(
                            "Update Cadenza Remote",
                            "Cadenza Host $host needs a newer Cadenza Remote. Update this Remote from Settings.",
                        ),
                )
            }
        }
        VersionGap.Same -> hostUpdateInstalls = 0
        VersionGap.Unknown -> Unit
    }
}

// A Host that has checked for an update installs it only when this Remote asked for the check, so a manual check still
// leaves the install to the button. Each automatic install is counted, so a Host that cannot take the update stops.
internal fun RemoteModel.installReadyHostUpdateAutomatically(status: HostUpdateStatus) {
    if (status.state != "ready" && status.state != "current" && status.state != "failed") return
    if (!hostUpdateCheckedAutomatically || status.state != "ready") {
        hostUpdateCheckedAutomatically = false
        return
    }
    hostUpdateCheckedAutomatically = false
    if (mutableState.value.snapshot?.playing == true || hostUpdateInstalls >= MAXIMUM_AUTOMATIC_HOST_UPDATES) return
    hostUpdateInstalls += 1
    installHostUpdate()
}

private const val MAXIMUM_AUTOMATIC_HOST_UPDATES = 2
