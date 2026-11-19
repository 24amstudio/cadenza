package app.cadenza.remote.energy

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Everything the UI may show about the current assessment. Inputs change often, so only Settings and Debug read it. */
data class EnergyState(
    val inputs: EnergyInputs = EnergyInputs(),
    val settings: EnergySettings = EnergySettings(),
    val assessment: EnergyAssessment = assessEnergy(inputs, settings),
    val profile: EnergyProfile = EnergyProfile.of(assessment.tier, settings),
)

/**
 * Holds the current energy decision. Inputs arrive from [EnergyMonitor] and settings from the user; either change
 * recomputes the decision at once. [profile] changes only when a knob changes, so the whole UI can read it without
 * recomposing for every battery percent.
 */
class EnergyAssessor(
    initialSettings: EnergySettings = EnergySettings(),
    private val persist: (EnergySettings) -> Unit = {},
) {
    private val mutableState = MutableStateFlow(EnergyState(settings = initialSettings))
    val state: StateFlow<EnergyState> = mutableState.asStateFlow()

    private val mutableProfile = MutableStateFlow(mutableState.value.profile)
    val profile: StateFlow<EnergyProfile> = mutableProfile.asStateFlow()

    fun onInputs(inputs: EnergyInputs) = update(inputs, null)

    /** Applies settings loaded from storage without writing them back. */
    fun restore(settings: EnergySettings) = update(null, settings)

    /** Applies [change] to the settings and persists the result. */
    fun updateSettings(change: (EnergySettings) -> EnergySettings) {
        val next = change(mutableState.value.settings)
        if (next == mutableState.value.settings) return
        update(null, next)
        persist(next)
    }

    private fun update(
        inputs: EnergyInputs?,
        settings: EnergySettings?,
    ) {
        val current = mutableState.value
        val nextInputs = inputs ?: current.inputs
        val nextSettings = settings ?: current.settings
        val assessment = assessEnergy(nextInputs, nextSettings)
        val profile = EnergyProfile.of(assessment.tier, nextSettings)
        mutableState.value = EnergyState(nextInputs, nextSettings, assessment, profile)
        mutableProfile.value = profile
    }
}
