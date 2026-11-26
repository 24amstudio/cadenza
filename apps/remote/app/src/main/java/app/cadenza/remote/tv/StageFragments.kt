package app.cadenza.remote.tv

import java.nio.ByteBuffer

/**
 * Pulls the samples out of one `moof` + `mdat` fragment, as the Host writes them for AC-3 and AAC. A 5.1 passthrough
 * sink needs the raw syncframes, so the fragment's sample table gives each frame's offset and size.
 */
internal object StageFragments {
    private const val TRUN_SIZES_PRESENT = 0x000200
    private const val TRUN_DATA_OFFSET_PRESENT = 0x000001
    private const val TRUN_DURATION_PRESENT = 0x000100

    fun samples(fragment: ByteArray): List<ByteArray>? {
        val buffer = ByteBuffer.wrap(fragment)
        val moof = findBox(fragment, 0, fragment.size, "moof") ?: return null
        val mdat = findBox(fragment, 0, fragment.size, "mdat") ?: return null
        val traf = findBox(fragment, moof.first + 8, moof.second - 8, "traf") ?: return null
        val trun = findBox(fragment, traf.first + 8, traf.second - 8, "trun") ?: return null
        val run = run(buffer, trun) ?: return null
        val mdatPayload = mdat.first + 8
        val base = moof.first
        val samples = ArrayList<ByteArray>(run.count)
        var offset = base + run.dataOffset
        for (size in run.sizes) {
            if (offset < mdatPayload || offset + size > fragment.size) return null
            samples += fragment.copyOfRange(offset, offset + size)
            offset += size
        }
        return samples
    }

    private data class Run(
        val count: Int,
        val dataOffset: Int,
        val sizes: List<Int>,
    )

    private fun run(
        buffer: ByteBuffer,
        box: Pair<Int, Int>,
    ): Run? {
        val start = box.first + 8
        val flags = buffer.getInt(start) and 0x00FF_FFFF
        val count = buffer.getInt(start + 4)
        var cursor = start + 8
        val dataOffset = if (flags and TRUN_DATA_OFFSET_PRESENT != 0) buffer.getInt(cursor).also { cursor += 4 } else 0
        if (count < 0 || count > 4_096) return null
        val sizes = ArrayList<Int>(count)
        repeat(count) {
            if (flags and TRUN_DURATION_PRESENT != 0) cursor += 4
            if (flags and TRUN_SIZES_PRESENT == 0) return null
            sizes += buffer.getInt(cursor)
            cursor += 4
        }
        return Run(count, dataOffset, sizes)
    }

    /** The payload start and total size of the first box of [type] between [from] and [from]+[length]. */
    private fun findBox(
        bytes: ByteArray,
        from: Int,
        length: Int,
        type: String,
    ): Pair<Int, Int>? {
        val buffer = ByteBuffer.wrap(bytes)
        var offset = from
        val end = from + length
        while (offset + 8 <= end) {
            val size = buffer.getInt(offset)
            if (size < 8 || offset + size > end) return null
            val name = String(bytes, offset + 4, 4, Charsets.ISO_8859_1)
            if (name == type) return offset to size
            offset += size
        }
        return null
    }
}
