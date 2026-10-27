package app.cadenza.remote

import app.cadenza.remote.network.EndpointPool
import app.cadenza.remote.network.LocalEndpoint
import org.junit.Assert.assertEquals
import org.junit.Test

class EndpointPoolTest {
    @Test
    fun failedWifiPathFallsBackToAnotherDiscoveredAddressAndRecovers() {
        val wifi = LocalEndpoint("192.168.1.20", 43127)
        val ethernet = LocalEndpoint("10.10.10.24", 43127)
        val pool = EndpointPool()
        pool.offer(wifi, 1)
        pool.offer(ethernet, 2)
        assertEquals(wifi, pool.next(wifi, 10))
        pool.failed(wifi, 11)
        assertEquals(ethernet, pool.next(wifi, 12))
        pool.succeeded(ethernet, 13)
        pool.failed(ethernet, 14)
        assertEquals(wifi, pool.next(wifi, 15))
        pool.succeeded(wifi, 16)
        assertEquals(wifi, pool.next(wifi, 17))
    }

    @Test
    fun staleDiscoveredAddressesExpireAndInvalidCandidatesAreIgnored() {
        val saved = LocalEndpoint("192.168.1.20", 43127)
        val pool = EndpointPool()
        pool.offer(LocalEndpoint("10.10.10.24", 43127), 1)
        pool.offer(LocalEndpoint("invalid", 80), 5)
        assertEquals(saved, pool.next(saved, 400_000))
    }
}
