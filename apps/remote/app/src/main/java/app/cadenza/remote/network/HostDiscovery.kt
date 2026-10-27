package app.cadenza.remote.network

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.RequiresApi
import java.util.concurrent.Executors

data class DiscoveredHost(
    val hostId: String,
    val address: String,
    val port: Int,
)

class HostDiscovery(
    context: Context,
    private val found: (DiscoveredHost) -> Unit,
) {
    private val manager = context.getSystemService(NsdManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private var modern: AutoCloseable? = null
    private val pending = ArrayDeque<NsdServiceInfo>()
    private var resolving = false
    private var running = false
    private val discovery =
        object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) = Unit

            override fun onDiscoveryStopped(serviceType: String) = Unit

            override fun onStartDiscoveryFailed(
                serviceType: String,
                errorCode: Int,
            ) {
                handler.post { running = false }
            }

            override fun onStopDiscoveryFailed(
                serviceType: String,
                errorCode: Int,
            ) {
                handler.post { running = false }
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) = Unit

            override fun onServiceFound(service: NsdServiceInfo) {
                handler.post {
                    if (!running || !service.serviceType.startsWith("_cadence._tcp")) return@post
                    if (Build.VERSION.SDK_INT >= 34) {
                        val resolver = modern as? ModernResolver ?: ModernResolver(manager, ::deliver).also { modern = it }
                        resolver.resolve(service)
                    } else if (pending.size < 32) {
                        pending.addLast(service)
                        resolveNext()
                    }
                }
            }
        }

    private fun deliver(
        info: NsdServiceInfo,
        address: String,
    ) {
        handler.post {
            if (!running) return@post
            val hostId = info.attributes["host_id"]?.toString(Charsets.UTF_8) ?: return@post
            if (!hostId.matches(Regex("[0-9a-f-]{36}")) || info.port !in 1024..65535) return@post
            found(DiscoveredHost(hostId, address, info.port))
        }
    }

    // HarmonyOS 4.3 needs the resolver available before Android API 34.
    @Suppress("DEPRECATION")
    private fun resolveNext() {
        if (resolving || pending.isEmpty() || !running) return
        resolving = true
        manager.resolveService(
            pending.removeFirst(),
            object : NsdManager.ResolveListener {
                override fun onResolveFailed(
                    serviceInfo: NsdServiceInfo,
                    errorCode: Int,
                ) = done()

                override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                    serviceInfo.host?.hostAddress?.let { deliver(serviceInfo, it) }
                    done()
                }

                private fun done() {
                    handler.post {
                        resolving = false
                        resolveNext()
                    }
                }
            },
        )
    }

    fun start() {
        if (running) return
        running = true
        runCatching { manager.discoverServices("_cadence._tcp.", NsdManager.PROTOCOL_DNS_SD, discovery) }
            .onFailure { running = false }
    }

    fun close() {
        if (running) runCatching { manager.stopServiceDiscovery(discovery) }
        running = false
        pending.clear()
        modern?.close()
        modern = null
    }

    @RequiresApi(34)
    private class ModernResolver(
        private val manager: NsdManager,
        private val deliver: (NsdServiceInfo, String) -> Unit,
    ) : AutoCloseable {
        private val executor = Executors.newSingleThreadExecutor()
        private val callbacks = mutableMapOf<String, NsdManager.ServiceInfoCallback>()

        fun resolve(service: NsdServiceInfo) {
            if (callbacks.containsKey(service.serviceName) || callbacks.size >= 32) return
            val callback =
                object : NsdManager.ServiceInfoCallback {
                    override fun onServiceInfoCallbackRegistrationFailed(errorCode: Int) = Unit

                    override fun onServiceUpdated(serviceInfo: NsdServiceInfo) {
                        serviceInfo.hostAddresses.filter { it.address.size == 4 }.forEach { address ->
                            deliver(serviceInfo, address.hostAddress.orEmpty())
                        }
                    }

                    override fun onServiceLost() = Unit

                    override fun onServiceInfoCallbackUnregistered() = Unit
                }
            callbacks[service.serviceName] = callback
            manager.registerServiceInfoCallback(service, executor, callback)
        }

        override fun close() {
            callbacks.values.forEach { runCatching { manager.unregisterServiceInfoCallback(it) } }
            callbacks.clear()
            executor.shutdown()
        }
    }
}
