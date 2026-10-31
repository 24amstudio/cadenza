package app.cadenza.remote.model

import app.cadenza.remote.updates.Changelog
import app.cadenza.remote.updates.RemoteUpdater
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

fun RemoteModel.showError(
    title: String,
    message: String,
) {
    reportLog("error", "ui.error", title + ": " + message)
    val now = System.currentTimeMillis()
    mutableState.update {
        it.copy(
            prompt = Prompt(title, message),
            debugLog = (it.debugLog + DebugLogEntry(now, title, message)).takeLast(200),
        )
    }
}

fun RemoteModel.dismissPrompt() {
    mutableState.update { it.copy(prompt = null) }
}

// Routes a failure by severity: a fatal Host problem interrupts with a modal, anything else is a snackbar.
internal fun RemoteModel.reportFailure(
    code: String?,
    title: String,
    message: String,
) {
    when (failureSeverity(code)) {
        FailureSeverity.Fatal -> if (mutableState.value.prompt?.message != message) showError(title, message)
        FailureSeverity.Warning -> showWarning(message)
    }
}

internal fun RemoteModel.showWarning(message: String) {
    reportLog("warning", "ui.warning", message)
    mutableState.update { it.copy(notice = Notice(message)) }
}

fun RemoteModel.dismissNotice(id: String) {
    mutableState.update { if (it.notice?.id == id) it.copy(notice = null) else it }
}

fun RemoteModel.checkUpdates(automatic: Boolean = false) {
    if (mutableState.value.updateBusy) return
    mutableState.update { it.copy(updateBusy = true) }
    updateScope.launch {
        try {
            val staged = withContext(updateDispatcher) { RemoteUpdater.checkAndStage(updateApp) }
            mutableState.update {
                it.copy(
                    updateBusy = false,
                    stagedUpdate = staged?.absolutePath,
                    notice = Notice(if (staged == null) "No newer release is available" else "Update ready to install"),
                )
            }
        } catch (error: Exception) {
            mutableState.update { it.copy(updateBusy = false) }
            if (!automatic) showError("Update could not be prepared", error.message ?: "Your existing installation is unchanged.")
        }
    }
}

fun RemoteModel.installing(value: Boolean) {
    mutableState.update { it.copy(installationBusy = value) }
}

fun RemoteModel.showChangelog(compare: Boolean = false) {
    if (mutableState.value.comparingChanges) return
    mutableState.update { it.copy(comparingChanges = compare) }
    updateScope.launch {
        try {
            val notes =
                withContext(updateDispatcher) {
                    if (compare) Changelog.compare(mutableState.value.updateConfiguration) else Changelog.bundled(updateApp)
                }
            mutableState.update { it.copy(changelog = notes) }
        } catch (error: Exception) {
            showError(
                "Changes could not be compared",
                error.message ?: "No comparison is available while offline. Your installation was not changed.",
            )
        } finally {
            mutableState.update { it.copy(comparingChanges = false) }
        }
    }
}

fun RemoteModel.dismissChangelog() {
    mutableState.update { it.copy(changelog = null) }
}

fun RemoteModel.installationResult() {
    installing(false)
    val error = RemoteUpdater.takeInstallationError(updateApp)
    if (error != null) showError("Update could not be installed", error)
}
