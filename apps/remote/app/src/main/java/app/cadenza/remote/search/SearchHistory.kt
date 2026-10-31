package app.cadenza.remote.search

// Recent searches stay on this Remote: newest first, without repeats, and capped so the list stays useful.
internal object SearchHistory {
    private const val LIMIT = 12
    private const val SEPARATOR = '\u001F'

    fun add(
        recent: List<String>,
        query: String,
    ): List<String> {
        val text = query.trim()
        if (text.isEmpty()) return recent
        val key = normalizeSearchText(text)
        return (listOf(text) + recent.filter { normalizeSearchText(it) != key }).take(LIMIT)
    }

    fun encode(recent: List<String>): String = recent.joinToString(SEPARATOR.toString()) { it.replace(SEPARATOR, ' ') }

    fun decode(raw: String?): List<String> =
        raw
            ?.split(SEPARATOR)
            ?.filter { it.isNotBlank() }
            ?.take(LIMIT)
            .orEmpty()
}
