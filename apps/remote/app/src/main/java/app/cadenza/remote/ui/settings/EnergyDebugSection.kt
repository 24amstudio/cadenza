package app.cadenza.remote.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cadenza.remote.energy.EnergyState
import app.cadenza.remote.energy.ThermalLevel
import app.cadenza.remote.ui.StatRow

/** The live energy tier, the device readings that produced it and the limits it applies. */
@Composable
internal fun EnergyDebugSection(energy: EnergyState) {
    val inputs = energy.inputs
    val profile = energy.profile
    Surface(shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surfaceContainerLow) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("Energy", style = MaterialTheme.typography.titleLarge)
            StatRow("Tier", energy.assessment.tier.label)
            StatRow("Reason", energy.assessment.message)
            StatRow("Mode", energy.settings.mode.label)
            StatRow("Battery", inputs.batteryPercent?.let { "$it%" } ?: "Unknown")
            StatRow("Charging", yesNo(inputs.charging))
            StatRow("System battery saver", yesNo(inputs.powerSave))
            StatRow("Temperature", thermalLabel(inputs.thermal))
            StatRow("Lyric frame cap", "${profile.lyricFrameCapFps} fps")
            StatRow("Lyric blur lines", if (profile.lyricBlurLines == 0) "Off" else "${profile.lyricBlurLines} each side")
            StatRow("Animated artwork", yesNo(profile.motionArtwork))
            StatRow("Cover decode size", "${profile.artworkMaxEdgePx} px")
            StatRow("Position ticks", "${profile.lyricTickMs} ms lyrics, ${profile.progressTickMs} ms timeline")
            StatRow("Status and clock", "${profile.statusIntervalMs / 1_000} s status, ${profile.clockPingMs / 1_000} s clock")
        }
    }
}

private fun yesNo(value: Boolean) = if (value) "Yes" else "No"

private fun thermalLabel(level: ThermalLevel) =
    when (level) {
        ThermalLevel.NORMAL -> "Normal"
        ThermalLevel.WARM -> "Warm"
        ThermalLevel.HOT -> "Hot"
    }
