package app.cadenza.remote.model

import app.cadenza.remote.energy.EnergyProfile
import app.cadenza.remote.energy.EnergySettings

// The monitor listens only while the app has a foreground control session or a playing, connected Host pins one.
// Anywhere else no receiver or thermal listener is registered.
internal fun RemoteModel.refreshEnergyMonitoring() {
    val value = mutable.value
    energyMonitor.setActive(foreground || (value.connected && value.snapshot?.playing == true))
}

fun RemoteModel.updateEnergySettings(change: (EnergySettings) -> EnergySettings) = energy.updateSettings(change)

// A tier change reaches the Host as a new session.status (the preference field follows the tier) and restores animated
// artwork that was skipped while Saver was on.
internal fun RemoteModel.energyProfileChanged(profile: EnergyProfile) {
    if (!mutable.value.connected) return
    publishStatus()
    val occurrence =
        mutable.value.snapshot
            ?.current
            ?.occurrenceId
    if (profile.motionArtwork && mutable.value.motion == null && occurrence != null) requestMotion(occurrence)
}
