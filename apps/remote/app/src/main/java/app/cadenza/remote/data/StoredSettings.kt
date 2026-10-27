package app.cadenza.remote.data

/** Small settings share the existing database's durable, checked transactions. */
class StoredSettings(
    private val database: CadenzaDatabase,
    private val namespace: String,
) {
    fun getString(
        key: String,
        fallback: String? = null,
    ): String? = database.setting("$namespace.$key") ?: fallback

    fun getLong(
        key: String,
        fallback: Long,
    ): Long = getString(key)?.toLongOrNull() ?: fallback

    fun getInt(
        key: String,
        fallback: Int,
    ): Int = getString(key)?.toIntOrNull() ?: fallback

    fun contains(key: String): Boolean = getString(key) != null

    fun write(vararg changes: Pair<String, String?>) {
        database.saveSettings(*changes.map { (key, value) -> "$namespace.$key" to value }.toTypedArray())
    }
}
