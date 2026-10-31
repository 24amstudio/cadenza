package app.cadenza.remote.network

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.ParcelUuid
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.ArrayDeque
import java.util.UUID

object BleTransportIds {
    val service: UUID = UUID.fromString("9f4c0001-4b9c-4f2d-9c2a-1c8f8b3d4a10")
    val write: UUID = UUID.fromString("9f4c0002-4b9c-4f2d-9c2a-1c8f8b3d4a10")
    val notify: UUID = UUID.fromString("9f4c0003-4b9c-4f2d-9c2a-1c8f8b3d4a10")
    val clientConfiguration: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
}

private const val MAXIMUM_MTU = 247
private const val MAXIMUM_CONNECT_ATTEMPTS = 3

private class BleFrameCodec {
    private val input = ByteArrayOutputStream()
    private var expected = -1

    fun encode(
        payload: ByteArray,
        mtu: Int,
    ): List<ByteArray> {
        require(payload.size <= 1_048_576) { "BLE frame is too large." }
        val framed =
            ByteBuffer
                .allocate(payload.size + 4)
                .order(ByteOrder.BIG_ENDIAN)
                .putInt(payload.size)
                .put(payload)
                .array()
        val chunkSize = (mtu - 3).coerceAtLeast(20)
        return framed.asList().chunked(chunkSize).map { it.toByteArray() }
    }

    fun append(chunk: ByteArray): List<ByteArray> {
        input.write(chunk)
        val result = mutableListOf<ByteArray>()
        while (true) {
            if (expected < 0 && input.size() >= 4) {
                val bytes = input.toByteArray()
                expected = ByteBuffer.wrap(bytes, 0, 4).order(ByteOrder.BIG_ENDIAN).int
                require(expected in 0..1_048_576) { "BLE frame length is invalid." }
                input.reset()
                input.write(bytes, 4, bytes.size - 4)
            }
            if (expected < 0 || input.size() < expected) return result
            val bytes = input.toByteArray()
            result += bytes.copyOf(expected)
            input.reset()
            input.write(bytes, expected, bytes.size - expected)
            expected = -1
        }
    }
}

@Suppress("DEPRECATION")
class BleTransport(
    private val context: Context,
    private val opened: () -> Unit,
    private val received: (ByteArray) -> Unit,
    private val closed: (String) -> Unit,
) {
    private val manager =
        context.getSystemService(
            BluetoothManager::class.java,
        )
    private val adapter: BluetoothAdapter? get() = manager?.adapter
    private val scanner get() = adapter?.bluetoothLeScanner
    private val frameCodec = BleFrameCodec()
    private val outbound = ArrayDeque<ByteArray>()
    private var gatt: BluetoothGatt? = null
    private var target: BluetoothDevice? = null
    private var connectAttempts = 0
    private var ready = false
    private var writeCharacteristic: BluetoothGattCharacteristic? = null
    private var notifyCharacteristic: BluetoothGattCharacteristic? = null
    private var mtu = 23
    private var writing = false
    private var scanning = false

    private val scanCallback =
        object : ScanCallback() {
            override fun onScanResult(
                callbackType: Int,
                result: ScanResult,
            ) {
                if (result.scanRecord?.serviceUuids?.any { it.uuid == BleTransportIds.service } == true) {
                    stopScan()
                    connect(result.device)
                }
            }

            override fun onScanFailed(errorCode: Int) {
                scanning = false
                closed("Bluetooth scan failed: $errorCode")
            }
        }

    private val callback =
        object : BluetoothGattCallback() {
            @SuppressLint("MissingPermission")
            override fun onConnectionStateChange(
                gatt: BluetoothGatt,
                status: Int,
                newState: Int,
            ) {
                if (target == null) return
                if (status == BluetoothGatt.GATT_SUCCESS && newState == BluetoothGatt.STATE_CONNECTED) {
                    if (!hasConnectPermission()) return close("Bluetooth permission is unavailable.")
                    // Discovery runs alone. Starting an MTU request in the same callback can stall it.
                    if (!gatt.discoverServices()) close("Cadenza Bluetooth services could not be discovered.")
                } else if (status != BluetoothGatt.GATT_SUCCESS || newState == BluetoothGatt.STATE_DISCONNECTED) {
                    if (!ready && connectAttempts < MAXIMUM_CONNECT_ATTEMPTS) {
                        openGatt(checkNotNull(target))
                    } else {
                        close("Bluetooth connection closed (GATT status $status).")
                    }
                }
            }

            @SuppressLint("MissingPermission")
            override fun onMtuChanged(
                gatt: BluetoothGatt,
                mtu: Int,
                status: Int,
            ) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    this@BleTransport.mtu = mtu
                }
                enableNotifications(gatt)
            }

            @SuppressLint("MissingPermission")
            override fun onServicesDiscovered(
                gatt: BluetoothGatt,
                status: Int,
            ) {
                if (status != BluetoothGatt.GATT_SUCCESS) return close("Bluetooth services unavailable.")
                if (!hasConnectPermission()) return close("Bluetooth permission is unavailable.")
                val service =
                    gatt
                        .getService(BleTransportIds.service)
                        ?: return close("Cadenza Bluetooth service unavailable.")
                writeCharacteristic = service.getCharacteristic(BleTransportIds.write)
                notifyCharacteristic = service.getCharacteristic(BleTransportIds.notify)
                if (notifyCharacteristic == null) {
                    return close("Cadenza Bluetooth notification channel unavailable.")
                }
                if (!gatt.requestMtu(MAXIMUM_MTU)) enableNotifications(gatt)
            }

            override fun onDescriptorWrite(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int,
            ) {
                if (descriptor.uuid == BleTransportIds.clientConfiguration && status == BluetoothGatt.GATT_SUCCESS) {
                    ready = true
                    opened()
                }
                if (descriptor.uuid == BleTransportIds.clientConfiguration && status != BluetoothGatt.GATT_SUCCESS) {
                    close("Could not enable Bluetooth notifications.")
                }
            }

            @Deprecated("Use the value overload on API 33 and newer.")
            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
            ) {
                if (characteristic.uuid != BleTransportIds.notify) return
                runCatching {
                    frameCodec.append(characteristic.value).forEach(received)
                }.onFailure { close(it.message ?: "Invalid Bluetooth frame.") }
            }

            override fun onCharacteristicWrite(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int,
            ) {
                if (characteristic.uuid != BleTransportIds.write) return
                writing = false
                if (status != BluetoothGatt.GATT_SUCCESS) return close("Bluetooth write failed.")
                flush()
            }
        }

    @SuppressLint("MissingPermission")
    fun startScan() {
        if (!hasScanPermission()) {
            closed("Allow Nearby devices to connect over Bluetooth.")
            return
        }
        if (scanning) return
        val scanner = scanner ?: return closed("Bluetooth is unavailable.")
        scanning = true
        scanner.startScan(
            listOf(
                ScanFilter
                    .Builder()
                    .setServiceUuid(ParcelUuid(BleTransportIds.service))
                    .build(),
            ),
            ScanSettings
                .Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build(),
            scanCallback,
        )
    }

    private fun hasConnectPermission(): Boolean =
        context.checkSelfPermission(android.Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED

    private fun hasScanPermission(): Boolean =
        context.checkSelfPermission(android.Manifest.permission.BLUETOOTH_SCAN) ==
            PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission")
    fun connect(device: BluetoothDevice) {
        stopScan()
        // Scan results can arrive again before stopScan takes effect. Only the first one starts a link.
        if (target != null) return
        target = device
        connectAttempts = 0
        openGatt(device)
    }

    @SuppressLint("MissingPermission")
    private fun openGatt(device: BluetoothDevice) {
        connectAttempts++
        gatt?.close()
        gatt =
            device.connectGatt(
                context,
                false,
                callback,
                BluetoothDevice.TRANSPORT_LE,
            )
    }

    @SuppressLint("MissingPermission")
    private fun enableNotifications(gatt: BluetoothGatt) {
        val notify =
            notifyCharacteristic
                ?: return close("Cadenza Bluetooth notification channel unavailable.")
        if (!gatt.setCharacteristicNotification(notify, true)) {
            return close("Could not enable Cadenza Bluetooth notifications.")
        }
        val descriptor =
            notify.getDescriptor(BleTransportIds.clientConfiguration)
                ?: return close("Cadenza Bluetooth notification descriptor unavailable.")
        descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
        if (!gatt.writeDescriptor(descriptor)) {
            return close("Could not enable Bluetooth notifications.")
        }
    }

    @SuppressLint("MissingPermission")
    fun send(payload: ByteArray): Boolean {
        if (writeCharacteristic == null) return false
        outbound.addAll(
            frameCodec.encode(payload, mtu),
        )
        flush()
        return true
    }

    @SuppressLint("MissingPermission")
    private fun flush() {
        if (writing) return
        val characteristic = writeCharacteristic ?: return
        if (outbound.isEmpty()) return
        val next = outbound.removeFirst()
        characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        characteristic.value = next
        writing = true
        if (gatt?.writeCharacteristic(characteristic) != true) {
            writing = false
            close("Bluetooth write could not be queued.")
        }
    }

    @SuppressLint("MissingPermission")
    fun stopScan() {
        if (!scanning) return
        scanner?.stopScan(scanCallback)
        scanning = false
    }

    @SuppressLint("MissingPermission")
    fun close(reason: String = "Bluetooth connection closed.") {
        stopScan()
        outbound.clear()
        writeCharacteristic = null
        notifyCharacteristic = null
        writing = false
        ready = false
        target = null
        connectAttempts = 0
        gatt?.disconnect()
        gatt?.close()
        gatt = null
        closed(reason)
    }
}
