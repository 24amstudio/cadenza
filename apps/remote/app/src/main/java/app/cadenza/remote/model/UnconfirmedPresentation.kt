package app.cadenza.remote.model

internal enum class UnconfirmedPresentation {
    Prompt,
    Notice,
    Quiet,
}

// Only a status check the user asked for may open the modal. Requests restored at launch or
// already explained by a prompt stay quiet, so reopening the app does not repeat the dialog.
internal fun unconfirmedPresentation(
    askedByUser: Boolean,
    resolved: Boolean,
    promptShowing: Boolean,
): UnconfirmedPresentation =
    when {
        askedByUser -> UnconfirmedPresentation.Prompt
        resolved || promptShowing -> UnconfirmedPresentation.Quiet
        else -> UnconfirmedPresentation.Notice
    }
