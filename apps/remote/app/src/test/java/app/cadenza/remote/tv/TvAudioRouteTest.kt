package app.cadenza.remote.tv

import org.junit.Assert.assertEquals
import org.junit.Test

class TvAudioRouteTest {
    @Test
    fun aFiveOneSendToAFiveOneOutputIsUnknownBecauseTheTvMayStillDownmix() {
        assertEquals(0, TvAudioSink.deliveredChannels(sent = 6, widest = 6, passthrough = false))
        assertEquals(0, TvAudioSink.deliveredChannels(sent = 6, widest = 8, passthrough = false))
    }

    @Test
    fun aFiveOneSendToAStereoOutputIsTheStereoThePlatformMixed() {
        assertEquals(2, TvAudioSink.deliveredChannels(sent = 6, widest = 2, passthrough = false))
    }

    @Test
    fun aStereoSendIsReportedAsStereo() {
        assertEquals(2, TvAudioSink.deliveredChannels(sent = 2, widest = 8, passthrough = false))
    }

    @Test
    fun anUnroutedOrUnknownOutputIsReportedAsUnknown() {
        assertEquals(0, TvAudioSink.deliveredChannels(sent = 2, widest = null, passthrough = false))
        assertEquals(0, TvAudioSink.deliveredChannels(sent = 6, widest = 0, passthrough = false))
    }

    @Test
    fun anAc3PassthroughIsUnknownBecauseTheReceiverDecodesIt() {
        assertEquals(0, TvAudioSink.deliveredChannels(sent = 6, widest = 8, passthrough = true))
    }
}
