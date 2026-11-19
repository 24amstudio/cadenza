package app.cadenza.remote.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.cadenza.remote.energy.EnergyMode
import app.cadenza.remote.energy.EnergySettings
import app.cadenza.remote.energy.EnergyTier
import app.cadenza.remote.energy.LOW_BATTERY_CHOICES
import app.cadenza.remote.model.RemoteModel
import app.cadenza.remote.model.updateEnergySettings
import app.cadenza.remote.ui.CadenzaIcon
import app.cadenza.remote.ui.ChoiceRow
import app.cadenza.remote.ui.SettingsCard

@Composable
internal fun EnergyCard(model: RemoteModel) {
    val energy by model.energyState.collectAsStateWithLifecycle()
    val settings = energy.settings

    fun change(edit: EnergySettings.() -> EnergySettings) = model.updateEnergySettings { it.edit() }
    SettingsCard(
        icon = CadenzaIcon.BATTERY,
        title = "Energy",
        supporting = "Cadenza lowers its effects when the device is low on power or hot.",
    ) {
        EnergyStatus(energy.assessment.tier, energy.assessment.message)
        Text("Mode", style = MaterialTheme.typography.labelLarge)
        ChoiceRow(
            options = EnergyMode.entries.map { it.name to it.label },
            selected = settings.mode.name,
            onSelected = { value -> change { copy(mode = EnergyMode.valueOf(value)) } },
        )
        if (settings.mode == EnergyMode.AUTOMATIC) {
            HorizontalDivider()
            SwitchRow(
                "Follow battery saver",
                "Use Saver whenever the system battery saver is on.",
                settings.followSystemSaver,
            ) { change { copy(followSystemSaver = it) } }
            Text("Switch to Saver at low battery", style = MaterialTheme.typography.labelLarge)
            ChoiceRow(
                options = LOW_BATTERY_CHOICES.map { it.toString() to if (it == 0) "Off" else "$it%" },
                selected = settings.lowBatteryPercent.toString(),
                onSelected = { value -> change { copy(lowBatteryPercent = value.toInt()) } },
            )
            SwitchRow(
                "Reduce effects while hot",
                "Lower effects when Android reports the device is warm or hot.",
                settings.reduceWhenHot,
            ) { change { copy(reduceWhenHot = it) } }
            SwitchRow(
                "Full effects while charging",
                "Keep every effect on while the device is plugged in.",
                settings.fullWhileCharging,
            ) { change { copy(fullWhileCharging = it) } }
        }
        HorizontalDivider()
        Text("Saver exceptions", style = MaterialTheme.typography.labelLarge)
        SwitchRow(
            "Animated artwork",
            "Keep album motion playing in Saver.",
            settings.motionArtworkInSaver,
        ) { change { copy(motionArtworkInSaver = it) } }
        SwitchRow(
            "Lyric blur",
            "Keep blur on the lines around the current lyric in Saver.",
            settings.lyricBlurInSaver,
        ) { change { copy(lyricBlurInSaver = it) } }
    }
}

@Composable
private fun EnergyStatus(
    tier: EnergyTier,
    message: String,
) {
    Surface(
        Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = "${tier.label} energy: $message" },
        shape = MaterialTheme.shapes.large,
        color =
            when (tier) {
                EnergyTier.FULL -> MaterialTheme.colorScheme.primaryContainer
                EnergyTier.BALANCED -> MaterialTheme.colorScheme.secondaryContainer
                EnergyTier.SAVER -> MaterialTheme.colorScheme.tertiaryContainer
            },
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(tier.label, style = MaterialTheme.typography.titleLarge)
            Text(message, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
private fun SwitchRow(
    title: String,
    supporting: String,
    checked: Boolean,
    onChange: (Boolean) -> Unit,
) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Text(supporting, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
        }
        Switch(checked = checked, onCheckedChange = onChange, modifier = Modifier.semantics { contentDescription = title })
    }
}
