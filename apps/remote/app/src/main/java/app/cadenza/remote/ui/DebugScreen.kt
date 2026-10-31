package app.cadenza.remote.ui

import android.app.ActivityManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Debug
import android.os.StatFs
import android.os.SystemClock
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import app.cadenza.remote.model.DebugLogEntry
import app.cadenza.remote.model.RemoteState
import kotlinx.coroutines.delay
import java.text.DateFormat
import java.util.Date

private data class DeviceStats(
    val cpuPercent: Double,
    val memoryBytes: Long,
    val memoryLimitBytes: Long,
    val storageUsedBytes: Long,
    val storageTotalBytes: Long,
)

@Composable
fun DebugScreen(
    state: RemoteState,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    val clipboard = context.getSystemService(ClipboardManager::class.java)
    var stats by remember { mutableStateOf(readStats(context, null)) }
    var previousCpu by remember { mutableStateOf<CpuSample?>(null) }
    var copied by remember { mutableStateOf(false) }
    val cutoff = System.currentTimeMillis() - 60 * 60 * 1_000L
    val recentErrors = state.debugLog.filter { it.timestampMs >= cutoff }
    LaunchedEffect(Unit) {
        while (true) {
            val sample = readCpuSample()
            stats = readStats(context, previousCpu)
            previousCpu = sample
            delay(1_000)
        }
    }
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            TextButton(onClick = onBack) { Text("Back to Settings") }
            Text("Debug", style = MaterialTheme.typography.headlineLarge)
        }
        Text(
            "These diagnostics stay on this device. Error history is kept for the current app session and limited to the last hour.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Surface(shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surfaceContainerLow) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Text("Device usage", style = MaterialTheme.typography.titleLarge)
                StatRow("CPU", if (stats.cpuPercent.isNaN()) "Sampling…" else "%.1f%%".format(stats.cpuPercent))
                StatRow("Memory", formatBytes(stats.memoryBytes) + " / " + formatBytes(stats.memoryLimitBytes))
                StatRow("Storage", formatBytes(stats.storageUsedBytes) + " used of " + formatBytes(stats.storageTotalBytes))
            }
        }
        Surface(shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surfaceContainerLow) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Text("Connection timing", style = MaterialTheme.typography.titleLarge)
                StatRow("Last command round trip", state.lastCommandLatencyMs?.let { "$it ms" } ?: "No sample yet")
                StatRow("Clock uncertainty", state.clockUncertaintyMs?.let { "≤ $it ms" } ?: "Synchronizing")
            }
        }
        Surface(shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surfaceContainerLow) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Errors in the last hour", style = MaterialTheme.typography.titleLarge)
                    if (recentErrors.isNotEmpty()) {
                        TextButton(onClick = {
                            clipboard.setPrimaryClip(ClipData.newPlainText("Cadenza Remote diagnostics", formatErrors(recentErrors)))
                            copied = true
                        }) { Text(if (copied) "Copied" else "Copy") }
                    }
                }
                if (recentErrors.isEmpty()) {
                    Text("No errors have been recorded in this session.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else {
                    recentErrors.asReversed().forEach { entry -> DebugError(entry) }
                }
            }
        }
    }
}

@Composable
private fun StatRow(
    label: String,
    value: String,
) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.titleMedium)
    }
}

@Composable
private fun DebugError(entry: DebugLogEntry) {
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(entry.title, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            Text(
                DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(entry.timestampMs)),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Text(entry.message, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

private data class CpuSample(
    val ticks: Long,
    val elapsedMs: Long,
)

private fun readCpuSample(): CpuSample? =
    runCatching {
        val fields =
            java.io
                .File("/proc/self/stat")
                .readText()
                .substringAfterLast(") ")
                .split(' ')
        CpuSample(fields[11].toLong() + fields[12].toLong(), SystemClock.elapsedRealtime())
    }.getOrNull()

private fun readStats(
    context: Context,
    previous: CpuSample?,
): DeviceStats {
    val memory = ActivityManager.MemoryInfo()
    (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memory)
    val process = Debug.MemoryInfo()
    Debug.getMemoryInfo(process)
    val storage = StatFs(context.filesDir.absolutePath)
    val cpu =
        previous?.let { sample ->
            val current = readCpuSample() ?: return@let Double.NaN
            ((current.ticks - sample.ticks).coerceAtLeast(0) / 100.0) /
                (current.elapsedMs - sample.elapsedMs).coerceAtLeast(1) * 100_000.0
        } ?: Double.NaN
    return DeviceStats(
        cpu,
        process.totalPss.toLong() * 1_024,
        memory.totalMem,
        appStorageBytes(context),
        storage.totalBytes,
    )
}

private fun appStorageBytes(context: Context): Long =
    listOf(context.filesDir, context.cacheDir, context.noBackupFilesDir)
        .sumOf { directorySize(it) }

private fun directorySize(directory: java.io.File): Long =
    directory.listFiles().orEmpty().sumOf { file ->
        if (file.isDirectory) directorySize(file) else file.length()
    }

internal fun formatBytes(bytes: Long): String {
    if (bytes < 1_024) return "$bytes B"
    val units = listOf("KB", "MB", "GB", "TB")
    var value = bytes.toDouble()
    var unit = -1
    while (value >= 1_024 && unit < units.lastIndex) {
        value /= 1_024
        unit++
    }
    return "%.1f %s".format(value, units[unit])
}

private fun formatErrors(errors: List<DebugLogEntry>): String =
    buildString {
        appendLine("Cadenza Remote errors from the last hour")
        errors.forEach { entry ->
            appendLine("${Date(entry.timestampMs)} — ${entry.title}")
            appendLine(entry.message)
            appendLine()
        }
    }
