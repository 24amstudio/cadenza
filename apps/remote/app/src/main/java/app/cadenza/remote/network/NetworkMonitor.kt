package app.cadenza.remote.network

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.os.Handler
import android.os.Looper
import android.os.SystemClock

class NetworkMonitor(
    context: Context,
    private val changed: () -> Unit,
) : AutoCloseable {
    private val manager = context.getSystemService(ConnectivityManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private var lastChangeAt = 0L
    private var registered = false
    private val callback =
        object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = notifyChanged()

            override fun onLost(network: Network) = notifyChanged()

            override fun onLinkPropertiesChanged(
                network: Network,
                linkProperties: LinkProperties,
            ) = notifyChanged()
        }

    private fun notifyChanged() {
        val now = SystemClock.elapsedRealtime()
        if (now - lastChangeAt < 750) return
        lastChangeAt = now
        handler.post { changed() }
    }

    fun start() {
        if (registered) return
        manager.registerDefaultNetworkCallback(callback)
        registered = true
    }

    override fun close() {
        if (registered) manager.unregisterNetworkCallback(callback)
        registered = false
    }
}
