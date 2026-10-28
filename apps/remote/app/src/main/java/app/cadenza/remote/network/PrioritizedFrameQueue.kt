package app.cadenza.remote.network

import org.json.JSONObject

/**
 * Keeps receipts and failures ahead of replicated state while replacing state that has not been applied yet.
 * The queue is synchronized because OkHttp invokes its producer from a socket thread.
 */
internal class PrioritizedFrameQueue(
    private val capacity: Int = 64,
) {
    data class Item(
        val version: Int,
        val frame: JSONObject,
    )

    private val priority = ArrayDeque<Item>()
    private val state = LinkedHashMap<Int, Item>()

    @Synchronized
    fun offer(item: Item): Boolean {
        if (isState(item.frame)) {
            state[item.version] = item
            return true
        }
        if (priority.size + state.size >= capacity) return false
        priority.addLast(item)
        return true
    }

    @Synchronized
    fun poll(): Item? =
        if (priority.isNotEmpty()) {
            priority.removeFirst()
        } else {
            state.entries.firstOrNull()?.let { state.remove(it.key) }
        }

    @Synchronized
    fun clear() {
        priority.clear()
        state.clear()
    }

    private fun isState(frame: JSONObject): Boolean = frame.optString("type") == "state" || frame.optString("type") == "heartbeat"
}
