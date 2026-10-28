package app.cadenza.remote

import app.cadenza.remote.network.PrioritizedFrameQueue
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PrioritizedFrameQueueTest {
    @Test
    fun priorityFramesAreDeliveredBeforeState() {
        val queue = PrioritizedFrameQueue()
        queue.offer(PrioritizedFrameQueue.Item(1, frame("state")))
        queue.offer(PrioritizedFrameQueue.Item(1, frame("command.result")))

        assertEquals("command.result", queue.poll()?.frame?.getString("type"))
        assertEquals("state", queue.poll()?.frame?.getString("type"))
    }

    @Test
    fun pendingStateIsReplacedWithoutDroppingReceipt() {
        val queue = PrioritizedFrameQueue(capacity = 2)
        queue.offer(PrioritizedFrameQueue.Item(1, frame("state", 1)))
        queue.offer(PrioritizedFrameQueue.Item(1, frame("command.result")))
        queue.offer(PrioritizedFrameQueue.Item(1, frame("state", 2)))

        assertEquals("command.result", queue.poll()?.frame?.getString("type"))
        assertEquals(2, queue.poll()?.frame?.getInt("sequence"))
        assertNull(queue.poll())
    }

    @Test
    fun fullPriorityQueueRejectsNewPriorityFrame() {
        val queue = PrioritizedFrameQueue(capacity = 1)
        assertTrue(queue.offer(PrioritizedFrameQueue.Item(1, frame("error"))))
        assertTrue(!queue.offer(PrioritizedFrameQueue.Item(1, frame("command.result"))))
    }

    private fun frame(
        type: String,
        sequence: Int? = null,
    ): JSONObject =
        JSONObject()
            .put("type", type)
            .apply { sequence?.let { put("sequence", it) } }
}
