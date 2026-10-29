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

    @Test
    fun repeatedlyFailedEndpointWaitsForCooldownBeforeRetry() {
        val saved = LocalEndpoint("192.168.1.20", 43127)
        val alternate = LocalEndpoint("10.10.10.24", 43127)
        val fresh = LocalEndpoint("172.16.0.30", 43127)
        val pool = EndpointPool()
        pool.offer(saved, 1)
        pool.offer(alternate, 2)
        pool.offer(fresh, 3)

        pool.failed(saved, 10)
        pool.failed(alternate, 11)
        assertEquals(fresh, pool.next(saved, 12))
        pool.failed(fresh, 13)
        assertEquals(saved, pool.next(saved, 500))
        assertEquals(saved, pool.next(saved, 1_010))
    }
}
