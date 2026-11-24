package app.cadenza.remote

import app.cadenza.remote.media.SessionDismissTimer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

class SessionDismissTimerTest {
    @Test
    fun aSessionThatStaysPausedIsDismissedOnceEvenWhenItIsReportedRepeatedly() =
        runBlocking {
            val dismissed = AtomicInteger()
            val timer = SessionDismissTimer(CoroutineScope(Dispatchers.Default), afterMs = 20) { dismissed.incrementAndGet() }

            timer.track(live = false)
            timer.track(live = false)
            delay(200)

            assertEquals(1, dismissed.get())
        }

    @Test
    fun playingAgainBeforeTheWaitEndsCancelsTheDismissal() =
        runBlocking {
            val dismissed = AtomicInteger()
            val timer = SessionDismissTimer(CoroutineScope(Dispatchers.Default), afterMs = 100) { dismissed.incrementAndGet() }

            timer.track(live = false)
            delay(20)
            timer.track(live = true)
            delay(250)

            assertEquals(0, dismissed.get())
        }
}
