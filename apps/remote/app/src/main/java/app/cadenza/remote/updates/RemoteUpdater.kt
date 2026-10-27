package app.cadenza.remote.updates

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.os.Build
import android.util.AtomicFile
import androidx.core.content.pm.PackageInfoCompat
import app.cadenza.remote.BuildConfig
import app.cadenza.remote.CadenzaApplication
import app.cadenza.remote.data.UpdateConfiguration
import org.json.JSONObject
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest

object RemoteUpdater {
    private fun preferences(context: Context) = (context.applicationContext as CadenzaApplication).updateSettings

    fun configuration(context: Context): UpdateConfiguration {
        val preferences = preferences(context)
        if (!preferences.contains("repository")) {
            return runCatching {
                val data =
                    context.assets
                        .open("release-config.json")
                        .bufferedReader()
                        .use { it.readText() }
                val value = JSONObject(data)
                UpdateConfiguration(value.getString("repository"), value.getString("public_key_spki_base64"))
            }.getOrDefault(UpdateConfiguration())
        }
        return UpdateConfiguration(preferences.getString("repository", "").orEmpty(), preferences.getString("key", "").orEmpty())
    }

    fun acceptConfiguration(
        context: Context,
        value: UpdateConfiguration,
    ) {
        if (value.repository.isBlank() || value.publicKeySpkiBase64.isBlank()) return
        require(ReleaseVerifier.repositoryValid(value.repository)) { "Host provided an invalid GitHub repository." }
        val previous = configuration(context)
        require(previous.publicKeySpkiBase64.isBlank() || previous == value) {
            "The release verification identity changed. Verify it on the Mac before reconfiguring updates."
        }
        preferences(context).write("repository" to value.repository, "key" to value.publicKeySpkiBase64)
        UpdateJob.schedule(context)
    }

    fun due(context: Context): Boolean =
        BuildConfig.AUTOMATIC_UPDATES && System.currentTimeMillis() - preferences(context).getLong("last_check", 0) >= 86_400_000 &&
            configuration(context).repository.isNotBlank()

    fun staged(context: Context): File? {
        val path = preferences(context).getString("staged", null) ?: return null
        val file = File(path)
        val directory = File(context.filesDir, "updates")
        return file.takeIf { it.isFile && it.parentFile?.canonicalPath == directory.canonicalPath && it.extension == "apk" }
    }

    fun takeInstallationError(context: Context): String? {
        val preferences = preferences(context)
        val error = preferences.getString("installation_error", null)
        preferences.write("installation_error" to null)
        return error
    }

    @Synchronized
    fun checkAndStage(context: Context): File? {
        check(BuildConfig.AUTOMATIC_UPDATES) { "Updates are disabled in " + BuildConfig.BUILD_PROFILE + " builds." }
        val config = configuration(context)
        check(ReleaseVerifier.repositoryValid(config.repository) && config.publicKeySpkiBase64.isNotEmpty()) {
            "Configure the GitHub repository and public release key in Cadenza Host, then reconnect."
        }
        val metadata = fetchReleaseMetadata(config)
        val manifest = metadata.manifest
        val signature = metadata.signature
        val verified = metadata.release
        val base = metadata.base
        if (verified.build <= BuildConfig.VERSION_CODE) {
            preferences(context).write("last_check" to System.currentTimeMillis().toString())
            return null
        }
        val directory = File(context.filesDir, "updates").apply { mkdirs() }
        val destination = File(directory, verified.asset.filename)
        if (destination.exists()) {
            ReleaseVerifier.verifyFile(destination, verified.asset)
        } else {
            val temporary = File(directory, "download.part")
            try {
                GitHubDownload.file(base + verified.asset.filename, temporary, verified.asset.size)
                ReleaseVerifier.verifyFile(temporary, verified.asset)
                verifyPackage(context, temporary, verified.build)
                Files.move(temporary.toPath(), destination.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
            } finally {
                temporary.delete()
            }
        }
        writeAtomic(File(directory, "cadenza-release.json"), manifest)
        writeAtomic(File(directory, "cadenza-release.sig"), signature)
        preferences(context).write("staged" to destination.absolutePath, "last_check" to System.currentTimeMillis().toString())
        directory.listFiles()?.filter { it.extension == "apk" && it != destination }?.forEach { it.delete() }
        return destination
    }

    private fun writeAtomic(
        file: File,
        bytes: ByteArray,
    ) {
        val atomic = AtomicFile(file)
        val stream = atomic.startWrite()
        try {
            stream.write(bytes)
            atomic.finishWrite(stream)
        } catch (error: Exception) {
            atomic.failWrite(stream)
            throw error
        }
    }

    private fun packageInfo(
        context: Context,
        archive: File?,
    ): PackageInfo {
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else legacySignatureFlag()
        return if (archive != null) {
            requireNotNull(context.packageManager.getPackageArchiveInfo(archive.absolutePath, flags)) { "The APK could not be read." }
        } else {
            context.packageManager.getPackageInfo(context.packageName, flags)
        }
    }

    // API 26–27 have no GET_SIGNING_CERTIFICATES replacement.
    @Suppress("DEPRECATION")
    private fun legacySignatureFlag(): Int = PackageManager.GET_SIGNATURES

    private fun verifyPackage(
        context: Context,
        file: File,
        build: Long,
    ) {
        val apk = packageInfo(context, file)
        val installed = packageInfo(context, null)
        require(apk.packageName == context.packageName && PackageInfoCompat.getLongVersionCode(apk) == build) {
            "The APK has an unexpected app identity or version."
        }
        val current = signers(installed, false)
        val incoming = signers(apk, true)
        require(current.isNotEmpty() && incoming.containsAll(current)) { "The APK signing identity does not match this installation." }
    }

    private fun signers(
        info: PackageInfo,
        history: Boolean,
    ): Set<String> {
        val certificates =
            if (Build.VERSION.SDK_INT >= 28) {
                val signing = requireNotNull(info.signingInfo) { "The APK has no signing identity." }
                if (history && !signing.hasMultipleSigners()) signing.signingCertificateHistory else signing.apkContentsSigners
            } else {
                legacySignatures(info)
            }
        return certificates
            .map { certificate ->
                MessageDigest
                    .getInstance(
                        "SHA-256",
                    ).digest(certificate.toByteArray())
                    .joinToString("") { "%02x".format(it.toInt() and 255) }
            }.toSet()
    }

    // API 26–27 expose signing certificates through the legacy field only.
    @Suppress("DEPRECATION")
    private fun legacySignatures(info: PackageInfo) = info.signatures.orEmpty()

    @Synchronized
    fun install(
        context: Context,
        file: File,
    ) {
        check(BuildConfig.AUTOMATIC_UPDATES) { "Updates are disabled in this build." }
        require(context.packageManager.canRequestPackageInstalls()) { "Allow app installs from Cadenza Remote first." }
        val directory = File(context.filesDir, "updates")
        require(file.canonicalPath.startsWith(directory.canonicalPath + File.separator) && file.extension == "apk") {
            "The update must be staged inside Cadenza."
        }
        val config = configuration(context)
        val verified =
            ReleaseVerifier.verify(
                File(directory, "cadenza-release.json").readBytes(),
                File(directory, "cadenza-release.sig").readBytes(),
                config.publicKeySpkiBase64,
                config.repository,
            )
        require(file.name == verified.asset.filename)
        ReleaseVerifier.verifyFile(file, verified.asset)
        verifyPackage(context, file, verified.build)
        val installer = context.packageManager.packageInstaller
        val previous = preferences(context).getInt("installation_session", -1)
        check(previous < 0 || installer.getSessionInfo(previous) == null) {
            "An update installation is already waiting for Android. Complete or cancel its confirmation first."
        }
        val parameters =
            PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
                setAppPackageName(context.packageName)
                setSize(file.length())
                if (Build.VERSION.SDK_INT >= 31) setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            }
        val sessionId = installer.createSession(parameters)
        try {
            preferences(context).write("installation_session" to sessionId.toString())
            installer.openSession(sessionId).use { session ->
                file.inputStream().use { input ->
                    session.openWrite("cadenza.apk", 0, file.length()).use { output ->
                        input.copyTo(output)
                        session.fsync(output)
                    }
                }
                val intent = Intent(context, InstallResultReceiver::class.java).setAction("app.cadenza.INSTALL_RESULT")
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
                val callback = PendingIntent.getBroadcast(context, sessionId, intent, flags)
                session.commit(callback.intentSender)
            }
        } catch (error: Exception) {
            installer.abandonSession(sessionId)
            preferences(context).write("installation_session" to null)
            throw error
        }
    }
}
