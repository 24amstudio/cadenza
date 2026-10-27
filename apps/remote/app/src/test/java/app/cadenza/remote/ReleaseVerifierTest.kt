package app.cadenza.remote

import app.cadenza.remote.updates.Changelog
import app.cadenza.remote.updates.ReleaseVerifier
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.security.KeyPairGenerator
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.util.Base64

class ReleaseVerifierTest {
    @Test
    fun authenticatedMetadataStillMustMatchRepositoryVersionAndDevice() {
        val key = KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()
        val publicKey = Base64.getEncoder().encodeToString(key.public.encoded)
        val manifest =
            JSONObject()
                .put("schema", 1)
                .put("protocol_major", 1)
                .put("repository", "example/cadenza")
                .put("version", "0.2.0")
                .put("tag", "v0.2.0")
                .put("build", 2)
                .put("build_id", "a".repeat(40))
                .put(
                    "changelog",
                    JSONArray()
                        .put(JSONObject().put("build", 1).put("version", "0.1.0").put("changes", JSONArray().put("Older change")))
                        .put(JSONObject().put("build", 2).put("version", "0.2.0").put("changes", JSONArray().put("New Favorites"))),
                ).put(
                    "assets",
                    JSONArray().put(
                        JSONObject()
                            .put("platform", "android")
                            .put("filename", "Cadenza-Remote-0.2.0.apk")
                            .put("sha256", "a".repeat(64))
                            .put("size", 100)
                            .put("minimum_os", 26),
                    ),
                )
        val data = manifest.toString().toByteArray()
        val signature =
            Signature.getInstance("SHA256withECDSA").run {
                initSign(key.private)
                update(data)
                sign()
            }
        val result = ReleaseVerifier.verify(data, signature, publicKey, "example/cadenza", 1, 30)
        assertEquals(2L, result.build)
        assertEquals("0.2.0\nNew Favorites", Changelog.relevantChanges(result, 1))
        assertEquals("a".repeat(40), result.buildIdentity)
        assertEquals("Cadenza-Remote-0.2.0.apk", result.asset.filename)
        assertThrows(IllegalArgumentException::class.java) {
            ReleaseVerifier.verify(data + byteArrayOf(32), signature, publicKey, "example/cadenza", 1, 30)
        }
        assertThrows(IllegalArgumentException::class.java) { ReleaseVerifier.verify(data, signature, publicKey, "someone/else", 1, 30) }
        assertThrows(IllegalArgumentException::class.java) { ReleaseVerifier.verify(data, signature, publicKey, "example/cadenza", 2, 30) }
        assertThrows(IllegalArgumentException::class.java) { ReleaseVerifier.verify(data, signature, publicKey, "example/cadenza", 1, 25) }
    }
}
