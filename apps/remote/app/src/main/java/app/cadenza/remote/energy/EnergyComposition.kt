package app.cadenza.remote.energy

import androidx.compose.runtime.staticCompositionLocalOf

/**
 * The knobs UI code reads. Static, because it changes only when a tier or setting changes, never for a battery
 * percent. Screens that show the live assessment collect `RemoteModel.energyState` themselves.
 */
val LocalEnergyProfile = staticCompositionLocalOf { EnergyProfile.Full }
