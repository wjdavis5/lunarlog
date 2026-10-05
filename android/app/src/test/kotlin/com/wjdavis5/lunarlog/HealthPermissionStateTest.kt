package com.wjdavis5.lunarlog

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Issue #1478: pins the `permissionStatus` decision the Android adapter
 * reports to Dart.
 *
 * Two things were wrong before it. A fresh install answered "denied" before
 * the person had been asked anything, because Android cannot tell "never
 * asked" from "denied" by looking at what is granted — and since the Dart
 * write pass stops on "denied" before its own authorization request, the
 * Android write path could never ask. And the status required every
 * requested permission but the background read, so declining an optional
 * READ permission (Health Connect's "Access past data") reported "denied"
 * and blocked every write.
 */
class HealthPermissionStateTest {

    private val writeMenstruation = "android.permission.health.WRITE_MENSTRUATION"
    private val writeSpotting =
        "android.permission.health.WRITE_INTERMENSTRUAL_BLEEDING"
    private val readMenstruation = "android.permission.health.READ_MENSTRUATION"
    private val readHistory = "android.permission.health.READ_HEALTH_DATA_HISTORY"
    private val readBackground =
        "android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND"

    /** What `permissionStatus` requires: the write permissions only. */
    private val required = setOf(writeMenstruation, writeSpotting)

    /** What the request sheet asks for: writes and reads together. */
    private val requested =
        required + setOf(readMenstruation, readHistory, readBackground)

    private fun status(granted: Set<String>, everRequested: Boolean): String =
        HealthPermissionState.statusFor(
            granted = granted,
            required = required,
            requested = requested,
            everRequested = everRequested,
        )

    @Test
    fun `a fresh install is not asked yet, never denied`() {
        assertEquals("notAsked", status(emptySet(), everRequested = false))
    }

    @Test
    fun `once the request has been launched, nothing granted is denied`() {
        assertEquals("denied", status(emptySet(), everRequested = true))
    }

    @Test
    fun `every write permission granted is granted`() {
        assertEquals("granted", status(required, everRequested = true))
    }

    @Test
    fun `granted does not depend on the remembered flag`() {
        // Granted in Health Connect's own settings, or by a build that asked
        // before the flag existed.
        assertEquals("granted", status(required, everRequested = false))
    }

    @Test
    fun `declining the read permissions does not deny the writes`() {
        // The person allowed every write and left "Access past data", the
        // background read, and the reads themselves off.
        assertEquals("granted", status(required, everRequested = true))
        assertEquals(
            "granted",
            status(required + readMenstruation, everRequested = true),
        )
    }

    @Test
    fun `a missing write permission is denied even with every read granted`() {
        assertEquals(
            "denied",
            status(
                setOf(writeMenstruation, readMenstruation, readHistory, readBackground),
                everRequested = true,
            ),
        )
    }

    @Test
    fun `a read-only grant proves the person was asked, so it is denied not unasked`() {
        // An install that answered the sheet before the flag existed, or a
        // permission switched on in Health Connect's settings: something is
        // granted, so a decision was made.
        assertEquals(
            "denied",
            status(setOf(readMenstruation), everRequested = false),
        )
    }

    @Test
    fun `a permission the app does not request proves nothing`() {
        assertEquals(
            "notAsked",
            status(setOf("android.permission.health.READ_STEPS"), everRequested = false),
        )
    }

    // The review of Issue #1478: access granted without this install's own
    // sheet (an older build's, or Health Connect's settings) and later
    // removed altogether must read "denied", not "not yet asked" — with a
    // forward-only cursor in place the write pass never asks again, so
    // "not yet asked" would leave every write failing with no Settings
    // link. The adapter sets its marker whenever provesAsked is true, which
    // turns the later revocation into everRequested = true.
    @Test
    fun `a grant of anything the app requests proves the person was asked`() {
        assertTrue(HealthPermissionState.provesAsked(required, requested))
        assertTrue(HealthPermissionState.provesAsked(setOf(readMenstruation), requested))
        assertTrue(HealthPermissionState.provesAsked(setOf(readBackground), requested))
    }

    @Test
    fun `nothing granted, or only something the app never requests, proves nothing`() {
        assertFalse(HealthPermissionState.provesAsked(emptySet(), requested))
        assertFalse(
            HealthPermissionState.provesAsked(
                setOf("android.permission.health.READ_STEPS"),
                requested,
            ),
        )
    }

    @Test
    fun `access seen granted and then removed altogether reads denied`() {
        // While granted, the adapter sees provesAsked and sets the marker...
        assertTrue(HealthPermissionState.provesAsked(required, requested))
        assertEquals("granted", status(required, everRequested = false))
        // ...so once everything is revoked the marker answers for it.
        assertEquals("denied", status(emptySet(), everRequested = true))
    }

    @Test
    fun `the wire strings are the Dart HealthPermissionStatus names`() {
        assertEquals("granted", HealthPermissionState.GRANTED)
        assertEquals("notAsked", HealthPermissionState.NOT_ASKED)
        assertEquals("denied", HealthPermissionState.DENIED)
    }
}
