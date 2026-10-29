package app.cadenza.remote.ui

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Size
import android.view.Surface
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.LuminanceSource
import com.google.zxing.MultiFormatReader
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.ReaderException
import com.google.zxing.Result
import com.google.zxing.ResultMetadataType
import com.google.zxing.common.HybridBinarizer
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

private val compactPairingMagic = byteArrayOf(0x43, 0x44, 0x5A, 0x50)

@Composable
fun QrScanner(
    onCode: (ByteArray) -> Unit,
    onError: (String) -> Unit,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val previewView =
        remember(context) {
            PreviewView(context).apply {
                scaleType = PreviewView.ScaleType.FILL_CENTER
                contentDescription = "Camera preview. Point at the pairing QR code in Cadenza Host."
            }
        }
    val scanner = remember { CameraScanner(context, onCode, onError) }
    DisposableEffect(scanner) {
        scanner.bind(lifecycleOwner, previewView)
        onDispose { scanner.close() }
    }
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        AndroidView(
            factory = { previewView },
            modifier =
                Modifier
                    .widthIn(max = 360.dp)
                    .fillMaxWidth()
                    .aspectRatio(1f)
                    .clip(MaterialTheme.shapes.large),
        )
    }
}

private class CameraScanner(
    private val context: Context,
    private val onCode: (ByteArray) -> Unit,
    private val onError: (String) -> Unit,
) : ImageAnalysis.Analyzer {
    private val main = Handler(Looper.getMainLooper())
    private val analysisExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val complete = AtomicBoolean(false)
    private val stopped = AtomicBoolean(false)
    private var provider: ProcessCameraProvider? = null
    private var lastAnalysis = 0L
    private var luminance = ByteArray(0)
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

    fun bind(
        owner: LifecycleOwner,
        view: PreviewView,
    ) {
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener(
            {
                if (stopped.get()) return@addListener
                try {
                    val cameraProvider = future.get()
                    provider = cameraProvider
                    bindUseCases(cameraProvider, owner, view)
                } catch (error: Exception) {
                    fail(error.message ?: "Could not open the camera.")
                }
            },
            ContextCompat.getMainExecutor(context),
        )
    }

    private fun bindUseCases(
        cameraProvider: ProcessCameraProvider,
        owner: LifecycleOwner,
        view: PreviewView,
    ) {
        check(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            "Camera permission is required to scan the pairing QR code."
        }
        val selector =
            if (cameraProvider.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA)) {
                CameraSelector.DEFAULT_BACK_CAMERA
            } else {
                CameraSelector.DEFAULT_FRONT_CAMERA
            }
        // The invitation QR is dense because it carries a base64 certificate, and smaller frames
        // decoded it erratically from a distance. CameraX picks the closest size the device supports.
        val analysis =
            ImageAnalysis
                .Builder()
                .setResolutionSelector(
                    ResolutionSelector
                        .Builder()
                        .setResolutionStrategy(
                            ResolutionStrategy(
                                Size(2_560, 1_920),
                                ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER,
                            ),
                        ).build(),
                ).setTargetRotation(view.display?.rotation ?: Surface.ROTATION_0)
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
                .also { it.setAnalyzer(analysisExecutor, this) }
        val preview = Preview.Builder().build().also { it.surfaceProvider = view.surfaceProvider }
        cameraProvider.unbindAll()
        val camera = cameraProvider.bindToLifecycle(owner, selector, preview, analysis)
        camera.cameraInfo.cameraState.observe(owner) { state ->
            if (state.error != null) fail("The camera is unavailable. Close other camera apps and retry the QR scan.")
        }
    }

    override fun analyze(image: ImageProxy) {
        image.use { frame ->
            val now = SystemClock.elapsedRealtime()
            if (complete.get() || stopped.get() || now - lastAnalysis < 200) return@use
            lastAnalysis = now
            val plane = frame.planes[0]
            val pixels = frame.width * frame.height
            if (luminance.size != pixels) luminance = ByteArray(pixels)
            extractLuminance(plane.rowStride, plane.pixelStride, frame.width, frame.height, plane.buffer, luminance)
            val payload = decodeQrPayload(luminance, frame.width, frame.height, frame.imageInfo.rotationDegrees, decoder)
            if (payload != null && !stopped.get() && complete.compareAndSet(false, true)) {
                main.post { onCode(payload) }
            }
        }
    }

    private fun fail(message: String) {
        if (complete.compareAndSet(false, true)) main.post { onError(message) }
    }

    fun close() {
        if (!stopped.compareAndSet(false, true)) return
        provider?.unbindAll()
        analysisExecutor.shutdown()
    }
}

internal fun decodeQrPayload(
    luminance: ByteArray,
    width: Int,
    height: Int,
    rotationDegrees: Int,
    decoder: MultiFormatReader,
): ByteArray? {
    val frame = PlanarYUVLuminanceSource(luminance, width, height, 0, 0, width, height, false)
    val crops = listOf(frame) + centeredQrCrops(frame)
    for (crop in crops) {
        val orientations = rotatedSources(crop, rotationDegrees)
        for (source in orientations) {
            try {
                val result = decoder.decodeWithState(BinaryBitmap(HybridBinarizer(source)))
                val payload = resultPayload(result)
                if (payload.size <= 4_096) return payload
            } catch (_: ReaderException) {
                // Try the next crop or orientation; camera frames are independent.
            } finally {
                decoder.reset()
            }
        }
    }
    return null
}

internal fun resultPayload(result: Result): ByteArray {
    val segments = result.resultMetadata?.get(ResultMetadataType.BYTE_SEGMENTS) as? List<*>
    val binary = segments?.filterIsInstance<ByteArray>()?.takeIf { it.isNotEmpty() }
    val segmented = binary?.fold(ByteArray(0)) { output, segment -> output + segment }
    if (segmented?.startsWith(compactPairingMagic) == true) return segmented
    val raw = result.rawBytes
    if (raw != null && raw.startsWith(compactPairingMagic)) return raw
    return segmented ?: result.text.toByteArray(Charsets.UTF_8)
}

private fun ByteArray.startsWith(prefix: ByteArray): Boolean =
    size >= prefix.size && prefix.indices.all { index -> this[index] == prefix[index] }

private fun rotatedSources(
    source: LuminanceSource,
    rotationDegrees: Int,
): List<LuminanceSource> {
    if (!source.isRotateSupported) return listOf(source)
    val turns = ((rotationDegrees % 360) + 360) % 360 / 90
    if (turns == 0) return listOf(source)
    var rotated = source
    repeat(turns) {
        rotated = rotated.rotateCounterClockwise()
    }
    return listOf(source, rotated)
}

private fun centeredQrCrops(source: LuminanceSource): List<LuminanceSource> {
    if (!source.isCropSupported) return emptyList()
    val width = source.width
    val height = source.height
    return listOf(0.88f, 0.72f).mapNotNull { fraction ->
        val cropWidth = (width * fraction).toInt()
        val cropHeight = (height * fraction).toInt()
        if (cropWidth < 1 || cropHeight < 1) {
            null
        } else {
            source.crop(
                (width - cropWidth) / 2,
                (height - cropHeight) / 2,
                cropWidth,
                cropHeight,
            )
        }
    }
}

// Copy only the luminance plane, row by row, instead of per pixel; TRY_HARDER and the
// inverted retry need every frame's full resolution to read codes at a distance.
internal fun extractLuminance(
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
