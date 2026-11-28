package app.cadenza.remote

import app.cadenza.remote.data.CastDevice
import app.cadenza.remote.data.CastState
import app.cadenza.remote.data.CastTransmitState
import app.cadenza.remote.data.StageDevice
import app.cadenza.remote.data.castingTargets
import org.junit.Assert.assertEquals
import org.junit.Test

class CastingTargetsTest {
    @Test
    fun nothingIsListedWhileNothingIsReceiving() {
        assertEquals(emptyList<String>(), castingTargets(cast = null, remoteAudioTarget = null))
        assertEquals(
            emptyList<String>(),
            castingTargets(cast = castState(transmit = transmit("starting")), remoteAudioTarget = null),
        )
    }

    @Test
    fun aGoogleCastDeviceIsListedByItsLabelOnceItIsTransmitting() {
        val cast =
            castState(
                devices = listOf(CastDevice(name = "dev-1", display = "none", label = "Living Room TV")),
                transmit = transmit("transmitting", device = "dev-1"),
            )

        assertEquals(listOf("Living Room TV"), castingTargets(cast = cast, remoteAudioTarget = null))
    }

    @Test
    fun aRemoteStreamAndACadenzaTvAreListedTogether() {
        val cast = castState(stages = listOf(StageDevice("tv-1", "Bedroom TV", transmitting = true)))

        assertEquals(
            listOf("Living Room iPad", "Bedroom TV"),
            castingTargets(cast = cast, remoteAudioTarget = "Living Room iPad"),
        )
    }

    @Test
    fun aTvThatIsNotReceivingIsNotListed() {
        val cast = castState(stages = listOf(StageDevice("tv-1", "Bedroom TV", transmitting = false)))

        assertEquals(emptyList<String>(), castingTargets(cast = cast, remoteAudioTarget = null))
    }

    private fun transmit(
        state: String,
        device: String? = null,
    ) = CastTransmitState(state = state, device = device, reason = null)

    private fun castState(
        devices: List<CastDevice> = emptyList(),
        transmit: CastTransmitState? = null,
        stages: List<StageDevice> = emptyList(),
    ) = CastState(presentation = "auto", devices = devices, transmit = transmit, stages = stages)
}
