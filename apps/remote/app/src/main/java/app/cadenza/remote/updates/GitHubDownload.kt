package app.cadenza.remote.updates

import app.cadenza.remote.data.readBounded
import java.io.File
import java.net.URL
import javax.net.ssl.HttpsURLConnection

object GitHubDownload {
    private val hosts = setOf("api.github.com", "github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com")

    private fun open(address: String): HttpsURLConnection {
        var url = URL(address)
        repeat(6) {
            require(url.protocol == "https" && url.host in hosts && url.userInfo == null && url.port in listOf(-1, 443)) {
                "Invalid GitHub download address."
            }
            val connection = url.openConnection() as HttpsURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 10_000
            connection.readTimeout = 20_000
            connection.setRequestProperty("User-Agent", "Cadenza-Remote")
            connection.setRequestProperty("Accept", "application/vnd.github+json")
            val status = connection.responseCode
            if (status in listOf(301, 302, 303, 307, 308)) {
                val next = connection.getHeaderField("Location")
                connection.disconnect()
                require(next != null) { "The download redirect was incomplete." }
                url = URL(url, next)
            } else {
                require(status == 200) { "GitHub returned HTTP " + status + ". Try again later." }
                return connection
            }
        }
        error("Too many GitHub redirects.")
    }

    fun bytes(
        address: String,
        maximum: Int,
    ): ByteArray {
        val connection = open(address)
        try {
            return connection.inputStream.use { it.readBounded(maximum) }
        } finally {
            connection.disconnect()
        }
    }

    fun file(
        address: String,
        destination: File,
        expectedSize: Long,
    ) {
        val connection = open(address)
        try {
            connection.inputStream.use { input ->
                destination.outputStream().use { output ->
                    val buffer = ByteArray(65_536)
                    var total = 0L
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        total += count
                        require(total <= expectedSize) { "The package exceeded its signed size." }
                        output.write(buffer, 0, count)
                    }
                    require(total == expectedSize) { "The package download was interrupted." }
                    output.fd.sync()
                }
            }
        } finally {
            connection.disconnect()
        }
    }
}
