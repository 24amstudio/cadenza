package app.cadenza.remote.ui.browse

import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.staticCompositionLocalOf
import app.cadenza.remote.data.BrowseTarget
import app.cadenza.remote.model.RemoteState

// The pages opened from Now Playing, song actions, or Search, newest last. The stack is saveable, so rotating the
// screen keeps the user on the page they were reading and Back steps through the pages they opened.
class BrowseNavigator(
    initial: List<BrowseTarget> = emptyList(),
) {
    val stack = mutableStateListOf<BrowseTarget>().apply { addAll(initial) }

    val current: BrowseTarget? get() = stack.lastOrNull()

    fun open(target: BrowseTarget) {
        if (stack.lastOrNull()?.key != target.key) stack.add(target)
    }

    fun back(): Boolean = stack.isNotEmpty().also { if (it) stack.removeAt(stack.lastIndex) }

    fun clear() = stack.clear()

    companion object {
        val Saver =
            listSaver<BrowseNavigator, String>(
                save = { navigator -> navigator.stack.map(BrowseTarget::encode) },
                restore = { saved -> BrowseNavigator(saved.mapNotNull(BrowseTarget::decode)) },
            )
    }
}

val LocalBrowseNavigator = staticCompositionLocalOf { BrowseNavigator() }

// A page needs a Host that browses. A song from Music's own queue has no identity the Host could resolve, so only its
// artist, which can be looked up by name, has a page.
fun canBrowse(
    state: RemoteState,
    target: BrowseTarget,
): Boolean {
    if ("library.browse" !in state.capabilities || !state.connected) return false
    target.song?.let { return it.source != "unknown" }
    return target.id != null || !target.artistName.isNullOrBlank()
}
