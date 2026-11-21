package app.cadenza.remote

import app.cadenza.remote.model.VersionGap
import app.cadenza.remote.model.versionGap
import org.junit.Assert.assertEquals
import org.junit.Test

class VersionGapTest {
    @Test
    fun theOlderBuildIsTheOneThatNeedsTheUpdate() {
        assertEquals(VersionGap.RemoteOlder, versionGap(remoteBuild = 10, hostBuild = 11))
        assertEquals(VersionGap.RemoteNewer, versionGap(remoteBuild = 12, hostBuild = 11))
        assertEquals(VersionGap.Same, versionGap(remoteBuild = 11, hostBuild = 11))
    }

    @Test
    fun aHostThatReportsNoBuildLeavesTheGapUnknown() {
        assertEquals(VersionGap.Unknown, versionGap(remoteBuild = 11, hostBuild = null))
    }
}
