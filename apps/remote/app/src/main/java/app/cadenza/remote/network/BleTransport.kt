package app.cadenza.remote.network

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.ParcelUuid
import android.os.SystemClock
import java.util.ArrayDeque
import java.util.UUID
import kotlin.random.Random

object BleTransportIds {
    val service: UUID = UUID.fromString("9f4c0001-4b9c-4f2d-9c2a-1c8f8b3d4a10")
    val write: UUID = UUID.fromString("9f4c0002-4b9c-4f2d-9c2a-1c8f8b3d4a10")
    val notify: UUID = UUID.fromString("9f4c0003-4b9c-4f2d-9c2a-1c8f8b3d4a10")
    val clientConfiguration: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
}

private const val MAXIMUM_MTU = 247
private const val DEFAULT_MTU = 23
private const val DISCONNECT_GRACE_MS = 400L
private const val RELAX_CHECK_MS = 3_000L

/** Where a link is in its setup. Only one step is outstanding at a time, because Android runs one GATT operation. */
private enum class Stage { IDLE, SCANNING, CONNECTING, DISCOVERING, NEGOTIATING, SUBSCRIBING, READY, CLOSED }

/**
 * One Bluetooth link to the Host.
 *
 * Every GATT callback, timer and state change runs on this transport's own handler thread (callbacks are forwarded by
 * onLink), so nothing here is shared between threads except the outbound queue, which has its own lock. Each step of
 * setup has a deadline, a failed attempt is closed before the next one starts, and nothing keeps a timer running while
 * the link is idle.
 */
@Suppress("DEPRECATION")
@SuppressLint("MissingPermission") // Every entry point checks BLUETOOTH_SCAN or BLUETOOTH_CONNECT first.
class BleTransport(
    private val context: Context,
    private val opened: () -> Unit,
    private val received: (ByteArray) -> Unit,
    private val closed: (String) -> Unit,
) {
    private val manager = context.getSystemService(BluetoothManager::class.java)
    private val adapter: BluetoothAdapter? get() = manager?.adapter
    private val thread = HandlerThread("cadenza-ble").apply { start() }
    private val handler = Handler(thread.looper)
    private val frameCodec = BleFrameCodec()
    private val bulk = BulkTransferTracker()

    private val lock = Any()
    private val outbound = ArrayDeque<ByteArray>()
    private var queuedBytes = 0

    @Volatile private var mtu = DEFAULT_MTU

    @Volatile private var ready = false

    private var stage = Stage.IDLE
    private var gatt: BluetoothGatt? = null
    private var target: BluetoothDevice? = null
    private var attempts = 0
    private var startedAt = 0L
    private var writeCharacteristic: BluetoothGattCharacteristic? = null
    private var notifyCharacteristic: BluetoothGattCharacteristic? = null
    private var writing = false
    private var scanning = false

    private val scanCallback =
        object : ScanCallback() {
            override fun onScanResult(
                callbackType: Int,
                result: ScanResult,
            ) {
                if (result.scanRecord?.serviceUuids?.any { it.uuid == BleTransportIds.service } == true) {
                    handler.post { if (stage == Stage.SCANNING) connect(result.device) }
                }
            }

            override fun onScanFailed(errorCode: Int) {
                handler.post {
                    scanning = false
                    if (stage == Stage.SCANNING) close("Bluetooth scan failed ($errorCode).")
                }
            }
        }

    // Android delivers GATT callbacks on a binder thread. Each one copies what it needs and moves to this transport's
    // handler thread at once, because a notification's value is a shared buffer that the next notification overwrites.
    private fun onLink(
        gatt: BluetoothGatt,
        block: () -> Unit,
    ) {
        handler.post { if (gatt === this.gatt) block() }
    }

    private val callback =
        object : BluetoothGattCallback() {
            override fun onConnectionStateChange(
                gatt: BluetoothGatt,
                status: Int,
                newState: Int,
            ) = onLink(gatt) {
                if (status == BluetoothGatt.GATT_SUCCESS && newState == BluetoothProfile.STATE_CONNECTED) {
                    if (stage != Stage.CONNECTING) return@onLink
                    if (!hasConnectPermission()) return@onLink close(BleLinkPolicy.PERMISSION_MESSAGE)
                    // Discovery runs alone. Starting an MTU request in the same callback can stall it.
                    stage = Stage.DISCOVERING
                    if (!gatt.discoverServices()) {
                        attemptFailed(status, "Cadenza Bluetooth services could not be discovered.")
                    }
                } else if (status != BluetoothGatt.GATT_SUCCESS || newState == BluetoothProfile.STATE_DISCONNECTED) {
                    if (stage == Stage.READY) {
                        close("Bluetooth link lost (GATT status $status).")
                    } else {
                        attemptFailed(status, "Bluetooth connection failed (GATT status $status).")
                    }
                }
            }

            override fun onServicesDiscovered(
                gatt: BluetoothGatt,
                status: Int,
            ) = onLink(gatt) {
                if (stage != Stage.DISCOVERING) return@onLink
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    return@onLink attemptFailed(status, "Bluetooth services unavailable.")
                }
                val service =
                    gatt.getService(BleTransportIds.service)
                        ?: return@onLink close("Cadenza Bluetooth service unavailable.")
                writeCharacteristic = service.getCharacteristic(BleTransportIds.write)
                notifyCharacteristic = service.getCharacteristic(BleTransportIds.notify)
                if (writeCharacteristic == null || notifyCharacteristic == null) {
                    return@onLink close("Cadenza Bluetooth channel unavailable.")
                }
                stage = Stage.NEGOTIATING
                // Some phones never answer the size request. The link still works at the default size.
                handler.postDelayed(negotiationTimeout, BleLinkPolicy.MTU_DEADLINE_MS)
                if (!gatt.requestMtu(MAXIMUM_MTU)) negotiationDone(gatt)
            }

            override fun onMtuChanged(
                gatt: BluetoothGatt,
                mtu: Int,
                status: Int,
            ) = onLink(gatt) {
                if (stage != Stage.NEGOTIATING) return@onLink
                if (status == BluetoothGatt.GATT_SUCCESS) this@BleTransport.mtu = mtu
                negotiationDone(gatt)
            }

            override fun onDescriptorWrite(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int,
            ) = onLink(gatt) {
                if (stage != Stage.SUBSCRIBING || descriptor.uuid != BleTransportIds.clientConfiguration) return@onLink
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    return@onLink attemptFailed(status, "Could not enable Bluetooth notifications (GATT status $status).")
                }
                handler.removeCallbacks(setupTimedOut)
                stage = Stage.READY
                ready = true
                opened()
            }

            // API 33 and newer deliver the value as its own array.
            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray,
            ) = notified(gatt, characteristic, value)

            @Deprecated("Replaced by the value overload on API 33 and newer.")
            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
            ) {
                characteristic.value?.let { notified(gatt, characteristic, it.copyOf()) }
            }

            override fun onCharacteristicWrite(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int,
            ) = onLink(gatt) {
                if (characteristic.uuid != BleTransportIds.write) return@onLink
                handler.removeCallbacks(writeTimedOut)
                writing = false
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    return@onLink close("Bluetooth write failed (GATT status $status).")
                }
                flush()
            }
        }

    private fun notified(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        value: ByteArray,
    ) = onLink(gatt) {
        if (stage != Stage.READY || characteristic.uuid != BleTransportIds.notify) return@onLink
        trackTransfer(value.size)
        runCatching { frameCodec.append(value).forEach(received) }
            .onFailure { close(it.message ?: "Invalid Bluetooth frame.") }
    }

    private val setupTimedOut = Runnable { attemptFailed(null, "Bluetooth setup timed out.") }
    private val writeTimedOut = Runnable { close("Bluetooth write timed out.") }
    private val negotiationTimeout =
        Runnable {
            val current = gatt
            if (stage == Stage.NEGOTIATING && current != null) negotiationDone(current)
        }
    private val relaxCheck =
        object : Runnable {
            override fun run() {
                if (stage != Stage.READY) return
                if (bulk.shouldRelax(SystemClock.elapsedRealtime())) {
                    gatt?.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_BALANCED)
                } else if (bulk.fast) {
                    handler.postDelayed(this, RELAX_CHECK_MS)
                }
            }
        }

    fun startScan() = onHandler { beginScan() }

    private fun beginScan() {
        if (stage != Stage.IDLE) return
        if (!hasScanPermission()) return close(BleLinkPolicy.PERMISSION_MESSAGE)
        val scanner = adapter?.bluetoothLeScanner ?: return close(BleLinkPolicy.UNAVAILABLE_MESSAGE)
        stage = Stage.SCANNING
        startedAt = SystemClock.elapsedRealtime()
        val wait = scanDelay()
        handler.postDelayed({ if (stage == Stage.SCANNING) startScanner(scanner) }, wait)
    }

    private fun startScanner(scanner: android.bluetooth.le.BluetoothLeScanner) {
        recordScanStart()
        scanning = true
        scanner.startScan(
            listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(BleTransportIds.service)).build()),
            ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(),
            scanCallback,
        )
        handler.postDelayed({
            if (stage == Stage.SCANNING) {
                close("Cadenza Host was not found over Bluetooth. Keep Bluetooth on near the Host.")
            }
        }, BleLinkPolicy.SCAN_WINDOW_MS)
    }

    private fun hasConnectPermission(): Boolean =
        context.checkSelfPermission(android.Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    private fun hasScanPermission(): Boolean =
        context.checkSelfPermission(android.Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED

    fun connect(device: BluetoothDevice) =
        onHandler {
            stopScan()
            // Scan results can arrive again before stopScan takes effect. Only the first one starts a link.
            if (target != null || stage == Stage.CLOSED) return@onHandler
            if (startedAt == 0L) startedAt = SystemClock.elapsedRealtime()
            target = device
            attempts = 0
            openGatt(device)
        }

    private fun openGatt(device: BluetoothDevice) {
        if (!hasConnectPermission()) return close(BleLinkPolicy.PERMISSION_MESSAGE)
        attempts++
        stage = Stage.CONNECTING
        handler.postDelayed(setupTimedOut, BleLinkPolicy.SETUP_DEADLINE_MS)
        // A direct connection (autoConnect false) is the fast path. Callbacks reach the handler through onLink.
        gatt =
            device.connectGatt(
                context,
                false,
                callback,
                BluetoothDevice.TRANSPORT_LE,
                BluetoothDevice.PHY_LE_1M_MASK,
            )
        if (gatt == null) attemptFailed(null, "Bluetooth connection could not be started.")
    }

    // One setup attempt did not work. The broken connection is closed first: reusing it, or reconnecting at once, is
    // what makes Android's GATT status 133 repeat.
    private fun attemptFailed(
        status: Int?,
        reason: String,
    ) {
        handler.removeCallbacks(setupTimedOut)
        handler.removeCallbacks(negotiationTimeout)
        val device = target
        val delay = BleLinkPolicy.retryDelayMs(attempts, Random.nextDouble())
        val elapsed = SystemClock.elapsedRealtime() - startedAt
        if (device == null || stage == Stage.CLOSED || stage == Stage.READY ||
            !BleLinkPolicy.retryable(status ?: -1, attempts, elapsed, delay)
        ) {
            return close(reason)
        }
        discardGatt()
        stage = Stage.CONNECTING
        handler.postDelayed({ if (stage == Stage.CONNECTING && gatt == null) openGatt(device) }, delay)
    }

    private fun negotiationDone(gatt: BluetoothGatt) {
        handler.removeCallbacks(negotiationTimeout)
        stage = Stage.SUBSCRIBING
        val notify = notifyCharacteristic ?: return close("Cadenza Bluetooth notification channel unavailable.")
        if (!gatt.setCharacteristicNotification(notify, true)) {
            return close("Could not enable Cadenza Bluetooth notifications.")
        }
        val descriptor =
            notify.getDescriptor(BleTransportIds.clientConfiguration)
                ?: return close("Cadenza Bluetooth notification descriptor unavailable.")
        descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
        if (!gatt.writeDescriptor(descriptor)) attemptFailed(null, "Could not enable Bluetooth notifications.")
    }

    // Large inbound transfers (artwork, motion, browse results) get the fast connection interval, then it is released.
    private fun trackTransfer(size: Int) {
        if (bulk.onBytes(SystemClock.elapsedRealtime(), size)) {
            gatt?.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH)
            handler.postDelayed(relaxCheck, RELAX_CHECK_MS)
        }
    }

    /** Queues one frame. False when the link is not ready or is not draining, so the caller can keep the frame. */
    fun send(payload: ByteArray): Boolean {
        if (!ready) return false
        val chunks = frameCodec.encode(payload, mtu)
        val bytes = chunks.sumOf { it.size }
        synchronized(lock) {
            if (queuedBytes + bytes > BleLinkPolicy.MAXIMUM_QUEUED_BYTES) return false
            queuedBytes += bytes
            outbound.addAll(chunks)
        }
        handler.post(::flush)
        return true
    }

    private fun flush() {
        if (writing || stage != Stage.READY) return
        val characteristic = writeCharacteristic ?: return
        val next =
            synchronized(lock) {
                outbound.pollFirst()?.also { queuedBytes -= it.size }
            } ?: return
        characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        characteristic.value = next
        writing = true
        handler.postDelayed(writeTimedOut, BleLinkPolicy.WRITE_DEADLINE_MS)
        if (gatt?.writeCharacteristic(characteristic) != true) {
            handler.removeCallbacks(writeTimedOut)
            writing = false
            close("Bluetooth write could not be queued.")
        }
    }

    private fun stopScan() {
        if (!scanning) return
        scanning = false
        runCatching { adapter?.bluetoothLeScanner?.stopScan(scanCallback) }
    }

    // Asks the controller to drop the link and closes the handle shortly after, so the Host sees the disconnect instead
    // of waiting for a supervision timeout.
    private fun discardGatt() {
        val old = gatt ?: return
        gatt = null
        writeCharacteristic = null
        notifyCharacteristic = null
        writing = false
        ready = false
        runCatching { old.disconnect() }
        handler.postDelayed({ runCatching { old.close() } }, DISCONNECT_GRACE_MS)
    }

    private fun resetOutbound() =
        synchronized(lock) {
            outbound.clear()
            queuedBytes = 0
        }

    /** Ends the link on purpose. The caller already knows, so [closed] is not called. */
    fun release() = onHandler { shutdown(null) }

    fun close(reason: String = "Bluetooth connection closed.") = onHandler { shutdown(reason) }

    private fun shutdown(reason: String?) {
        if (stage == Stage.CLOSED) return
        stage = Stage.CLOSED
        stopScan()
        handler.removeCallbacksAndMessages(null)
        resetOutbound()
        bulk.reset()
        target = null
        discardGatt()
        // The delayed close above must still run, so the thread outlives it by a moment.
        handler.postDelayed({ thread.quitSafely() }, DISCONNECT_GRACE_MS * 2)
        if (reason != null) closed(reason)
    }

    private fun onHandler(block: () -> Unit) {
        if (Looper.myLooper() == thread.looper) block() else handler.post(block)
    }

    private fun scanDelay(): Long = synchronized(scanStarts) { BleLinkPolicy.scanStartDelayMs(scanStarts, SystemClock.elapsedRealtime()) }

    private fun recordScanStart() =
        synchronized(scanStarts) {
            val now = SystemClock.elapsedRealtime()
            scanStarts.removeAll { now - it > BleLinkPolicy.SCAN_HISTORY_MS }
            scanStarts.add(now)
        }

    private companion object {
        // Scan starts of every transport in this process, because Android's frequency limit is per app.
        val scanStarts = mutableListOf<Long>()
    }
}
