package com.wjdavis5.lunarlog

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Issue #992: pins the native paging-cursor format on the Android side.
 *
 * The Dart loop treats the cursor as opaque and only compares cursors for
 * progress, so the Swift half uses a different (anchor) encoding; what must
 * hold on THIS side is that every mode round-trips its token, that the two
 * range modes are distinguishable, that malformed input decodes to null
 * (never a crash or a silent wrong mode), and that a token containing the
 * separator or base64-unfriendly bytes still round-trips.
 */
class HealthImportCursorTest {

    // Issue #1549: turning "Access past data" on after the first import
    // imported nothing, because the first whole-range read had minted a
    // change token and every later pass asked only for what changed.

    private fun step(token: Boolean, reached: Boolean?, granted: Boolean) =
        HealthImportCursor.pastReadStep(
            tokenStored = token, reachedPast = reached, pastDataGranted = granted)

    @Test
    fun `a whole-range read is owed once past data is granted after a read that could not reach it`() {
        assertEquals(HealthImportCursor.PastReadStep.REREAD, step(true, false, true))
    }

    @Test
    fun `a token minted before this was recorded is not known to have reached it`() {
        assertEquals(HealthImportCursor.PastReadStep.REREAD, step(true, null, true))
    }

    @Test
    fun `nothing is owed when the stored token already stands for a read that reached it`() {
        assertEquals(HealthImportCursor.PastReadStep.NONE, step(true, true, true))
    }

    @Test
    fun `a changes pass with past data off stops the token standing for a read that reached it`() {
        // On, then off, then on again: older records another app wrote
        // meanwhile are behind the token, so the whole range is owed again.
        assertEquals(HealthImportCursor.PastReadStep.LOWER, step(true, true, false))
        assertEquals(HealthImportCursor.PastReadStep.REREAD, step(true, false, true))
    }

    @Test
    fun `with past data off and nothing to lower the pass is left alone`() {
        assertEquals(HealthImportCursor.PastReadStep.NONE, step(true, false, false))
        assertEquals(HealthImportCursor.PastReadStep.NONE, step(true, null, false))
    }

    @Test
    fun `with no token the next read is the whole range anyway`() {
        for (reached in listOf(null, false, true)) {
            for (granted in listOf(false, true)) {
                assertEquals(
                    HealthImportCursor.PastReadStep.NONE, step(false, reached, granted))
            }
        }
    }

    @Test
    fun `the stored answer reads back as written, and anything else is unknown`() {
        assertEquals(true, HealthImportCursor.reachedPastFromWire(
            HealthImportCursor.reachedPastToWire(true)))
        assertEquals(false, HealthImportCursor.reachedPastFromWire(
            HealthImportCursor.reachedPastToWire(false)))
        assertNull(HealthImportCursor.reachedPastFromWire(null))
        assertNull(HealthImportCursor.reachedPastFromWire(""))
        assertNull(HealthImportCursor.reachedPastFromWire("true"))
        // The two values differ, or "reached" could never be told apart.
        assertTrue(HealthImportCursor.REACHED_PAST != HealthImportCursor.REACHED_RECENT)
    }

    @Test
    fun `changes cursor round-trips its token`() {
        val cursor = HealthImportCursor.changes("abc123+/=")
        val decoded = HealthImportCursor.decode(cursor)!!
        assertTrue(HealthImportCursor.isChanges(decoded.mode))
        assertEquals("abc123+/=", decoded.token)
    }

    @Test
    fun `flow cursor round-trips a token and an empty token means first page`() {
        val withToken = HealthImportCursor.decode(HealthImportCursor.flow("tok"))!!
        assertTrue(HealthImportCursor.isFlow(withToken.mode))
        assertEquals("tok", withToken.token)

        val firstPage = HealthImportCursor.decode(HealthImportCursor.flow(null))!!
        assertTrue(HealthImportCursor.isFlow(firstPage.mode))
        assertNull(firstPage.token)
    }

    @Test
    fun `intermenstrual cursor round-trips and is not mistaken for flow`() {
        val decoded =
            HealthImportCursor.decode(HealthImportCursor.intermenstrual("tok"))!!
        assertTrue(HealthImportCursor.isIntermenstrual(decoded.mode))
        assertFalse(HealthImportCursor.isFlow(decoded.mode))
        assertFalse(HealthImportCursor.isChanges(decoded.mode))
        assertEquals("tok", decoded.token)
    }

    @Test
    fun `a token containing the separator or unicode still round-trips`() {
        for (token in listOf("a:b:c", "ünïcödé", "x".repeat(4096))) {
            val decoded = HealthImportCursor.decode(HealthImportCursor.changes(token))!!
            assertEquals(token, decoded.token)
        }
    }

    @Test
    fun `malformed cursors decode to null`() {
        assertNull(HealthImportCursor.decode(""))
        assertNull(HealthImportCursor.decode("noseparator"))
        assertNull(HealthImportCursor.decode(":missingmode"))
        assertNull(HealthImportCursor.decode("unknown:tok"))
        // A payload that is not valid base64url.
        assertNull(HealthImportCursor.decode("flow:***"))
    }
}
