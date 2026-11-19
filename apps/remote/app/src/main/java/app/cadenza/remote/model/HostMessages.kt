package app.cadenza.remote.model

private val scriptFailure = Regex("""^.*\.js: execution error: (?:Error: )*(.*?)(?: \((-?\d+)\))?$""", RegexOption.DOT_MATCHES_ALL)

// Music's scripting errors arrive with the script path and an AppleScript code. The path means nothing to a listener,
// so the toast shows the reason and the original text stays in the Host log.
internal fun friendlyHostMessage(message: String): String {
    val reason =
        scriptFailure
            .matchEntire(message.trim())
            ?.groupValues
            ?.get(1)
            ?.trim() ?: return message
    return when {
        reason.contains("library track is unavailable", ignoreCase = true) ->
            "Music can no longer find this song in your library. Search for it again to play it."
        reason.isBlank() -> "Music could not complete this request."
        else -> reason.replaceFirstChar(Char::uppercase).trimEnd('.') + "."
    }
}
