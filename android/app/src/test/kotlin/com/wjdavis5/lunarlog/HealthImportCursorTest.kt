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
