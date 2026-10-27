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
import android.hardware.camera2.params.OutputConfiguration
import android.hardware.camera2.params.SessionConfiguration
import android.media.ImageReader
import android.os.Build
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
    private val decoder =
        MultiFormatReader().apply {
            setHints(mapOf(DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE)))
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
                "Camera permission is required. You can paste pairing details instead."
            }
            val manager = context.getSystemService(CameraManager::class.java)
            val id =
                manager.cameraIdList.firstOrNull {
                    manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
                } ?: manager.cameraIdList.firstOrNull() ?: error("This device has no camera.")
            val map = manager.getCameraCharacteristics(id).get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val size =
                map
                    ?.getOutputSizes(ImageFormat.YUV_420_888)
                    ?.filter { it.width <= 1_280 && it.height <= 960 }
                    ?.minByOrNull { kotlin.math.abs(it.width * it.height - 640 * 480) } ?: error("QR capture is unavailable.")
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
                        fail("The camera disconnected. Paste pairing details or retry.")
                    }

                    override fun onError(
                        camera: CameraDevice,
                        error: Int,
                    ) {
                        camera.close()
                        fail("The camera is unavailable. Close other camera apps or paste pairing details.")
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
                            android.hardware.camera2.CaptureRequest.CONTROL_AF_MODE,
                            android.hardware.camera2.CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE,
                        )
                        configured.setRepeatingRequest(request.build(), null, handler)
                    } catch (error: Exception) {
                        fail(error.message ?: "Could not start camera preview.")
                    }
                }

                override fun onConfigureFailed(session: CameraCaptureSession) {
                    fail("Camera preview could not start. Paste pairing details instead.")
                }
            }
        if (Build.VERSION.SDK_INT >= 28) {
            camera.createCaptureSession(
                SessionConfiguration(
                    SessionConfiguration.SESSION_REGULAR,
                    surfaces.map(::OutputConfiguration),
                    Executor { handler.post(it) },
                    callback,
                ),
            )
        } else {
            createLegacySession(camera, surfaces, callback)
        }
    }

    // API 26–27 have only this session API. Newer systems use SessionConfiguration.
    @Suppress("DEPRECATION")
    private fun createLegacySession(
        camera: CameraDevice,
        surfaces: List<Surface>,
        callback: CameraCaptureSession.StateCallback,
    ) {
        camera.createCaptureSession(surfaces, callback, handler)
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
            for (y in 0 until image.height) {
                for (x in 0 until image.width) {
                    val index = y * plane.rowStride + x * plane.pixelStride
                    if (index >= buffer.limit()) return
                    data[y * image.width + x] = buffer.get(index)
                }
            }
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
