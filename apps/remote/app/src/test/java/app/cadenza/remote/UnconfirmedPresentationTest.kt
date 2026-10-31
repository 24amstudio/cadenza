package app.cadenza.remote

import app.cadenza.remote.model.UnconfirmedPresentation
import app.cadenza.remote.model.unconfirmedPresentation
import org.junit.Assert.assertEquals
import org.junit.Test

class UnconfirmedPresentationTest {
    @Test
    fun restoredRequestsNeverOpenThePromptOnTheirOwn() {
        assertEquals(
            UnconfirmedPresentation.Notice,
            unconfirmedPresentation(askedByUser = false, resolved = false, promptShowing = false),
        )
        assertEquals(
            UnconfirmedPresentation.Quiet,
            unconfirmedPresentation(askedByUser = false, resolved = true, promptShowing = false),
        )
        assertEquals(
            UnconfirmedPresentation.Quiet,
            unconfirmedPresentation(askedByUser = false, resolved = false, promptShowing = true),
        )
    }

    @Test
    fun aStatusCheckTheUserAskedForAlwaysExplainsTheOutcome() {
        assertEquals(
            UnconfirmedPresentation.Prompt,
            unconfirmedPresentation(askedByUser = true, resolved = false, promptShowing = false),
        )
        assertEquals(
            UnconfirmedPresentation.Prompt,
            unconfirmedPresentation(askedByUser = true, resolved = true, promptShowing = true),
        )
    }
}
