package app.cadenza.remote.network

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network

class NetworkMonitor(
    context: Context,
    private val changed: () -> Unit,
) : AutoCloseable {
    private val manager = context.getSystemService(ConnectivityManager::class.java)
    private var registered = false
    private val callback =
        object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = changed()

            override fun onLost(network: Network) = changed()

            override fun onLinkPropertiesChanged(
                network: Network,
                linkProperties: LinkProperties,
            ) = changed()
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
