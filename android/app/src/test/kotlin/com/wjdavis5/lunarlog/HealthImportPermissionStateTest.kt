package com.wjdavis5.lunarlog

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Issue #1491: pins the `importPermissionStatus` decision — the read-side
 * status the Dart background import pass is gated on.
 *
 * Before it, that pass was gated on `permissionStatus`, which answers for
 * the WRITE permissions. A person who let lunarlog read from Health Connect
 * and not write to it had a tap import that worked, a background import
 * that never ran, and a screen that promised one. The read-side status is
 * decided on the two record reads the import performs and on nothing else.
 */
class HealthImportPermissionStateTest {

    private val readMenstruation = "android.permission.health.READ_MENSTRUATION"
    private val readSpotting =
        "android.permission.health.READ_INTERMENSTRUAL_BLEEDING"
    private val readHistory = "android.permission.health.READ_HEALTH_DATA_HISTORY"
    private val readBackground =
        "android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND"
    private val writeMenstruation = "android.permission.health.WRITE_MENSTRUATION"
    private val writeSpotting =
        "android.permission.health.WRITE_INTERMENSTRUAL_BLEEDING"

    /** What the import reads: the two record types, and nothing else. */
    private val importReads = setOf(readMenstruation, readSpotting)

    private val writes = setOf(writeMenstruation, writeSpotting)

    /** What the request sheet asks for: writes and reads together. */
    private val requested = writes + importReads + setOf(readHistory, readBackground)

    private fun importStatus(granted: Set<String>, everRequested: Boolean): String =
        HealthPermissionState.importStatusFor(
            granted = granted,
            importReads = importReads,
            requested = requested,
            everRequested = everRequested,
        )

    private fun writeStatus(granted: Set<String>, everRequested: Boolean): String =
        HealthPermissionState.statusFor(
            granted = granted,
            required = writes,
            requested = requested,
            everRequested = everRequested,
        )

    @Test
    fun `reads on and every write off is granted for the import`() {
        // The case the issue is about. The write status for the same grant
        // is "denied", which is why the background pass never ran.
        assertEquals("granted", importStatus(importReads, everRequested = true))
        assertEquals("denied", writeStatus(importReads, everRequested = true))
    }

    @Test
    fun `the optional extras are not needed`() {
        // "Access past data" and the background read left off: the pass
        // still reads. (The worker checks the background read itself before
        // it wakes Dart; it is not this status's to decide.)
        assertEquals("granted", importStatus(importReads, everRequested = true))
        assertEquals(
            "granted",
            importStatus(importReads + readHistory + readBackground, everRequested = true),
        )
    }

    @Test
    fun `the optional extras are not enough`() {
        assertEquals(
            "denied",
            importStatus(setOf(readHistory, readBackground), everRequested = true),
        )
    }

    @Test
    fun `one read missing is not granted`() {
        // The pass reads both record types; half of it would fail.
        assertEquals("denied", importStatus(setOf(readMenstruation), everRequested = true))
        assertEquals("denied", importStatus(setOf(readSpotting), everRequested = true))
    }

    @Test
    fun `every write on and the reads off is denied for the import`() {
        // The mirror image: the write status is "granted", the import's is
        // not, and neither answers for the other.
        assertEquals("denied", importStatus(writes, everRequested = true))
        assertEquals("granted", writeStatus(writes, everRequested = true))
    }

    @Test
    fun `everything granted is granted for both`() {
        assertEquals("granted", importStatus(requested, everRequested = true))
        assertEquals("granted", writeStatus(requested, everRequested = true))
    }

    @Test
    fun `a fresh install is not asked yet, never denied`() {
        assertEquals("notAsked", importStatus(emptySet(), everRequested = false))
    }

    @Test
    fun `asked and nothing granted is denied`() {
        assertEquals("denied", importStatus(emptySet(), everRequested = true))
    }

    @Test
    fun `a grant of anything the app requests proves the person was asked`() {
        // No marker (the read-side status never sets one), but a write is
        // granted: a decision was made, so the missing reads are a denial.
        assertEquals("denied", importStatus(setOf(writeMenstruation), everRequested = false))
    }

    @Test
    fun `granted does not depend on the remembered flag`() {
        // Reads switched on in Health Connect's own settings.
        assertEquals("granted", importStatus(importReads, everRequested = false))
    }

    @Test
    fun `a permission the app does not request proves nothing`() {
        assertEquals(
            "notAsked",
            importStatus(setOf("android.permission.health.READ_STEPS"), everRequested = false),
        )
    }

    @Test
    fun `the two statuses agree on whether the person has been asked`() {
        // Whenever neither is granted, they tell "not asked" from "denied"
        // the same way: the read-side status is the write-side decision
        // over a different required set, not a second rule.
        for (everRequested in listOf(false, true)) {
            for (granted in listOf(emptySet(), setOf(readHistory), setOf(readBackground))) {
                assertEquals(
                    writeStatus(granted, everRequested),
                    importStatus(granted, everRequested),
                )
            }
        }
    }
}
