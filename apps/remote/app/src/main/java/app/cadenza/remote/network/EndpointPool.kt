package app.cadenza.remote.network

data class LocalEndpoint(
    val address: String,
    val port: Int,
)

/** Candidates never carry trust: the paired certificate is verified on every connection. */
class EndpointPool {
    private data class Candidate(
        val endpoint: LocalEndpoint,
        var seenAt: Long,
        var failedAt: Long? = null,
    )

    private val candidates = mutableListOf<Candidate>()

    fun offer(
        endpoint: LocalEndpoint,
        now: Long,
    ) {
        if (endpoint.port !in 1024..65535 || endpoint.address.length !in 1..253) return
        candidates.firstOrNull { it.endpoint == endpoint }?.let {
            it.seenAt = now
            return
        }
        if (candidates.size >= 8) candidates.removeAt(0)
        candidates.add(Candidate(endpoint, now))
    }

    fun next(
        fallback: LocalEndpoint,
        now: Long,
    ): LocalEndpoint {
        candidates.removeAll { now - it.seenAt > 300_000 && it.endpoint != fallback }
        offer(fallback, now)
        return candidates.minWith(compareBy<Candidate> { it.failedAt ?: Long.MIN_VALUE }.thenByDescending { it.seenAt }).endpoint
    }

    fun failed(
        endpoint: LocalEndpoint,
        now: Long,
    ) {
        candidates.firstOrNull { it.endpoint == endpoint }?.failedAt = now
    }

    fun succeeded(
        endpoint: LocalEndpoint,
        now: Long,
    ) {
        offer(endpoint, now)
        candidates.firstOrNull { it.endpoint == endpoint }?.failedAt = null
    }

    fun clear() = candidates.clear()
}
