package app.cadenza.remote.model

// Fatal failures need the user to act outside the control they just used, so they open a modal. Every other
// failure is a warning: it appears as a snackbar and never takes focus from the screen.
internal enum class FailureSeverity {
    Warning,
    Fatal,
}

internal fun failureSeverity(code: String?): FailureSeverity =
    when (code) {
        "music_permission",
        "authentication",
        "revoked",
        "tls",
        "secure_storage",
        "storage",
        "database_corrupt",
        "database_version",
        -> FailureSeverity.Fatal
        else -> FailureSeverity.Warning
    }
