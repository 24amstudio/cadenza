package app.cadenza.remote

import app.cadenza.remote.model.VolumeRocker
import org.junit.Assert.assertEquals
import org.junit.Test

class VolumeRockerTest {
    @Test
    fun eachPressMovesMusicByOneStepAndStopsAtTheEnds() {
        assertEquals(55, VolumeRocker.target(50, up = true))
        assertEquals(45, VolumeRocker.target(50, up = false))
        assertEquals(100, VolumeRocker.target(98, up = true))
        assertEquals(0, VolumeRocker.target(3, up = false))
    }
}
