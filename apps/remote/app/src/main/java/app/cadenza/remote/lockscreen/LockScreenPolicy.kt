package app.cadenza.remote.lockscreen

/** When the motion lock screen opens and when it closes. It is a visual layer over the keyguard, never a control surface. */
object LockScreenPolicy {
    fun shouldOpen(
        motionEnabled: Boolean,
        hasMotionArtwork: Boolean,
        playing: Boolean,
        connected: Boolean,
        screenOff: Boolean,
    ): Boolean = motionEnabled && hasMotionArtwork && playing && connected && screenOff

    fun shouldClose(
        playing: Boolean,
        connected: Boolean,
        userPresent: Boolean,
    ): Boolean = userPresent || !playing || !connected
}
