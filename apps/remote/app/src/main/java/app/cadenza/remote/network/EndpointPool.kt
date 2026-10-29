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
        var failures: Int = 0,
    )

    private val candidates = mutableListOf<Candidate>()
    private val retryCooldowns = longArrayOf(0, 1_000, 2_000, 4_000, 8_000, 30_000)

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
        val eligible =
            candidates.filter { candidate ->
                val failedAt = candidate.failedAt
                failedAt == null || now - failedAt >= retryCooldowns[candidate.failures]
            }
        val selected =
            eligible.minWithOrNull(
                compareBy<Candidate> { it.failedAt ?: Long.MIN_VALUE }.thenByDescending { it.seenAt },
            )
        return selected?.endpoint ?: candidates.minBy { it.failedAt ?: Long.MIN_VALUE }.endpoint
    }

    fun failed(
        endpoint: LocalEndpoint,
        now: Long,
    ) {
        candidates.firstOrNull { it.endpoint == endpoint }?.let {
            it.failedAt = now
            it.failures = (it.failures + 1).coerceAtMost(5)
        }
    }

    fun succeeded(
        endpoint: LocalEndpoint,
        now: Long,
    ) {
        offer(endpoint, now)
        candidates.firstOrNull { it.endpoint == endpoint }?.let {
            it.failedAt = null
            it.failures = 0
        }
    }

    fun clear() = candidates.clear()
}
