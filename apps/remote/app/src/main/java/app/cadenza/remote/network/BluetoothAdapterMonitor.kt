package app.cadenza.remote.network

import android.bluetooth.BluetoothAdapter
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.core.content.ContextCompat

/** Reports when the Bluetooth adapter is switched on, so a Bluetooth session can reconnect without a manual retry. */
class BluetoothAdapterMonitor(
    private val context: Context,
    private val enabled: () -> Unit,
) : AutoCloseable {
    private var registered = false

    private val receiver =
        object : BroadcastReceiver() {
            override fun onReceive(
                context: Context,
                intent: Intent,
            ) {
                val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
                if (state == BluetoothAdapter.STATE_ON) enabled()
            }
        }

    fun start() {
        if (registered) return
        ContextCompat.registerReceiver(
            context,
            receiver,
            IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        registered = true
    }

    override fun close() {
        if (registered) runCatching { context.unregisterReceiver(receiver) }
        registered = false
    }
}
