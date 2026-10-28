package app.cadenza.remote.ui

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.params.OutputConfiguration
import android.hardware.camera2.params.SessionConfiguration
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.view.Surface
import android.view.TextureView
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.ReaderException
import com.google.zxing.common.HybridBinarizer
import java.nio.ByteBuffer
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicBoolean

@Composable
fun QrScanner(
    onCode: (String) -> Unit,
    onError: (String) -> Unit,
) {
    val context = LocalContext.current
    val scanner = remember { CameraScanner(context, onCode, onError) }
    DisposableEffect(scanner) {
        onDispose { scanner.close() }
    }
    AndroidView(
        factory = {
            TextureView(it).apply {
                contentDescription = "Camera preview. Point at the pairing QR code in Cadenza Host."
                scanner.attach(this)
            }
        },
        modifier = Modifier.fillMaxWidth().height(360.dp),
    )
}

private class CameraScanner(
    private val context: Context,
    private val onCode: (String) -> Unit,
    private val onError: (String) -> Unit,
) {
    private val thread = HandlerThread("Cadenza QR").apply { start() }
    private val handler = Handler(thread.looper)
    private val main = Handler(Looper.getMainLooper())
    private val complete = AtomicBoolean(false)
    private val stopped = AtomicBoolean(false)
    private var device: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var images: ImageReader? = null
    private var preview: Surface? = null
    private var lastAnalysis = 0L
    private var afMode = CaptureRequest.CONTROL_AF_MODE_AUTO
    private val decoder =
        MultiFormatReader().apply {
            setHints(
                mapOf(
                    DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE),
                    DecodeHintType.TRY_HARDER to true,
                    DecodeHintType.ALSO_INVERTED to true,
                ),
            )
        }

    fun attach(view: TextureView) {
        view.surfaceTextureListener =
            object : TextureView.SurfaceTextureListener {
                override fun onSurfaceTextureAvailable(
                    surface: SurfaceTexture,
                    width: Int,
                    height: Int,
                ) = open(surface)

                override fun onSurfaceTextureSizeChanged(
                    surface: SurfaceTexture,
                    width: Int,
                    height: Int,
                ) = Unit

                override fun onSurfaceTextureUpdated(surface: SurfaceTexture) = Unit

                override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
                    close()
                    return true
                }
            }
        if (view.isAvailable) view.surfaceTexture?.let(::open)
    }

    private fun open(texture: SurfaceTexture) {
        if (stopped.get()) return
        try {
            check(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                "Camera permission is required to scan the pairing QR code."
            }
            val manager = context.getSystemService(CameraManager::class.java)
            val id =
                manager.cameraIdList.firstOrNull {
                    manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
                } ?: manager.cameraIdList.firstOrNull() ?: error("This device has no camera.")
            val map = manager.getCameraCharacteristics(id).get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            // A larger analysis frame reads smaller codes from farther away; the bulk
            // luminance copy below keeps decoding cheap enough for this size.
            val size =
                map
                    ?.getOutputSizes(ImageFormat.YUV_420_888)
                    ?.filter { it.width <= 1_920 && it.height <= 1_440 }
                    ?.maxByOrNull { it.width * it.height } ?: error("QR capture is unavailable.")
            afMode =
                manager
                    .getCameraCharacteristics(id)
                    .get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES)
                    ?.let { modes ->
                        when {
                            modes.contains(CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE) ->
                                CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE
                            modes.contains(CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO) ->
                                CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO
                            else -> CaptureRequest.CONTROL_AF_MODE_AUTO
                        }
                    } ?: CaptureRequest.CONTROL_AF_MODE_AUTO
            texture.setDefaultBufferSize(size.width, size.height)
            preview = Surface(texture)
            images =
                ImageReader.newInstance(size.width, size.height, ImageFormat.YUV_420_888, 2).apply {
                    setOnImageAvailableListener({ reader -> analyze(reader) }, handler)
                }
            manager.openCamera(
                id,
                object : CameraDevice.StateCallback() {
                    override fun onOpened(camera: CameraDevice) {
                        if (stopped.get()) {
                            camera.close()
                            return
                        }
                        device = camera
                        createSession(camera)
                    }

                    override fun onDisconnected(camera: CameraDevice) {
                        camera.close()
                        fail("The camera disconnected. Return to pairing and retry the QR scan.")
                    }

                    override fun onError(
                        camera: CameraDevice,
                        error: Int,
                    ) {
                        camera.close()
                        fail("The camera is unavailable. Close other camera apps and retry the QR scan.")
                    }
                },
                handler,
            )
        } catch (error: Exception) {
            fail(error.message ?: "Could not open the camera.")
        }
    }

    private fun createSession(camera: CameraDevice) {
        val surfaces = listOfNotNull(preview, images?.surface)
        val callback =
            object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(configured: CameraCaptureSession) {
                    if (stopped.get()) {
                        configured.close()
                        return
                    }
                    session = configured
                    try {
                        val request = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                        surfaces.forEach(request::addTarget)
                        request.set(
                            CaptureRequest.CONTROL_AF_MODE,
                            afMode,
                        )
                        configured.setRepeatingRequest(request.build(), null, handler)
                    } catch (error: Exception) {
                        fail(error.message ?: "Could not start camera preview.")
                    }
                }

                override fun onConfigureFailed(session: CameraCaptureSession) {
                    fail("Camera preview could not start. Return to pairing and retry the QR scan.")
                }
            }
        camera.createCaptureSession(
            SessionConfiguration(
                SessionConfiguration.SESSION_REGULAR,
                surfaces.map(::OutputConfiguration),
                Executor { handler.post(it) },
                callback,
            ),
        )
    }

    private fun analyze(reader: ImageReader) {
        val captured =
            try {
                reader.acquireLatestImage()
            } catch (_: IllegalStateException) {
                return
            }
        captured?.use { image ->
            val now = SystemClock.elapsedRealtime()
            if (complete.get() || stopped.get() || now - lastAnalysis < 200) return
            lastAnalysis = now
            val plane = image.planes[0]
            val data = ByteArray(image.width * image.height)
            val buffer = plane.buffer
            extractLuminance(plane.rowStride, plane.pixelStride, image.width, image.height, buffer, data)
            val source = PlanarYUVLuminanceSource(data, image.width, image.height, 0, 0, image.width, image.height, false)
            try {
                val result = decoder.decodeWithState(BinaryBitmap(HybridBinarizer(source)))
                if (result.text.length <= 4_096 && complete.compareAndSet(false, true)) main.post { onCode(result.text) }
            } catch (_: ReaderException) {
                // No readable QR in this frame; the next frame is independent.
            } finally {
                decoder.reset()
            }
        }
    }

    // Copy only the luminance plane, row by row, instead of per pixel; TRY_HARDER and the
    // inverted retry need every frame's full resolution to read codes at a distance.
    private fun extractLuminance(
        rowStride: Int,
        pixelStride: Int,
        width: Int,
        height: Int,
        buffer: ByteBuffer,
        data: ByteArray,
    ) {
        buffer.rewind()
        if (pixelStride == 1) {
            if (rowStride == width) {
                buffer.get(data, 0, minOf(data.size, buffer.remaining()))
                return
            }
            for (y in 0 until height) {
                val start = y * rowStride
                if (start + width > buffer.limit()) break
                buffer.position(start)
                buffer.get(data, y * width, width)
            }
            return
        }
        for (y in 0 until height) {
            for (x in 0 until width) {
                val index = y * rowStride + x * pixelStride
                if (index >= buffer.limit()) break
                data[y * width + x] = buffer.get(index)
            }
        }
    }

    private fun fail(message: String) {
        if (complete.compareAndSet(false, true)) main.post { onError(message) }
    }

    fun close() {
        if (!stopped.compareAndSet(false, true)) return
        session?.close()
        device?.close()
        images?.close()
        preview?.release()
        thread.quitSafely()
    }
}
