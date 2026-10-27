package app.cadenza.remote.data

import java.io.ByteArrayOutputStream
import java.io.InputStream

fun InputStream.readBounded(maximum: Int): ByteArray {
    require(maximum in 1..16_777_216)
    val output = ByteArrayOutputStream()
    val buffer = ByteArray(8_192)
    while (true) {
        val count = read(buffer)
        if (count < 0) return output.toByteArray()
        check(output.size() <= maximum - count) { "The response exceeded its size limit." }
        output.write(buffer, 0, count)
    }
}
