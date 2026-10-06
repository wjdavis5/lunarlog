package com.wjdavis5.lunarlog

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
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

    /**
     * Everything the app requests: the write path's sheet asks for all of
     * it, the import's own (issue #1515) for the reads and the two extras.
     */
    private val requested = writes + importReads + setOf(readHistory, readBackground)

    /**
     * `everRequested` is the read side's "asked": either request was
     * launched, since both carry the reads (issue #1515).
     */
    private fun importStatus(granted: Set<String>, everRequested: Boolean): String =
        HealthPermissionState.importStatusFor(
            granted = granted,
            importReads = importReads,
            requested = requested,
            everRequested = everRequested,
        )

    /** `everRequested` is the write side's: the WRITE request was launched. */
    private fun writeStatus(granted: Set<String>, everRequested: Boolean): String =
        HealthPermissionState.writeStatusFor(
            granted = granted,
            writes = writes,
            writesEverRequested = everRequested,
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

    // Issue #1515. Until it, one request carried everything, so the two
    // statuses could never disagree about whether the person had been
    // asked. The import has a request of its own now, for the reads alone,
    // so they can disagree — in one direction only.
    @Test
    fun `asked for the reads by the import is not asked for the writes`() {
        // The import's request was launched and she declined it: the reads
        // are denied, and the writes have still never been shown to her.
        assertEquals("denied", importStatus(emptySet(), everRequested = true))
        assertEquals("notAsked", writeStatus(emptySet(), everRequested = false))
        // She allowed them instead: reading is on, and the write path can
        // still ask.
        assertEquals("granted", importStatus(importReads, everRequested = true))
        assertEquals("notAsked", writeStatus(importReads, everRequested = false))
    }

    @Test
    fun `a granted read extra proves the reads were asked for, not the writes`() {
        // No marker at all: "access past data" or background access was
        // switched on somewhere. Every place that offers those offers the
        // record reads, so the missing reads are a denial; none of it says
        // a write permission was shown.
        for (granted in listOf(setOf(readHistory), setOf(readBackground))) {
            assertEquals("denied", importStatus(granted, everRequested = false))
            assertEquals("notAsked", writeStatus(granted, everRequested = false))
        }
    }

    @Test
    fun `asked for the writes always means asked for the reads`() {
        // The write path's request carries the reads beside the writes, so
        // its marker counts for both sides: the adapter's read-side
        // `everRequested` is true whenever the write side's is.
        for (granted in listOf(emptySet(), setOf(readHistory), setOf(readBackground))) {
            assertEquals("denied", writeStatus(granted, everRequested = true))
            assertEquals("denied", importStatus(granted, everRequested = true))
        }
        // And so does a granted write, with no marker anywhere.
        assertEquals("writingSome", writeStatus(setOf(writeMenstruation), everRequested = false))
        assertEquals("denied", importStatus(setOf(writeMenstruation), everRequested = false))
    }

    @Test
    fun `with nothing asked and nothing granted both are not asked yet`() {
        assertEquals("notAsked", writeStatus(emptySet(), everRequested = false))
        assertEquals("notAsked", importStatus(emptySet(), everRequested = false))
    }

    // Issue #1515: when a tap of Import raises its permission request at
    // all. Only when the import cannot read.
    private fun mustAsk(granted: Set<String>): Boolean =
        HealthPermissionState.importMustAsk(granted, importReads)

    @Test
    fun `reads on and writes off, a tap of Import asks for nothing`() {
        // The person the issue is about: no sheet at all.
        assertFalse(mustAsk(importReads))
    }

    @Test
    fun `an optional extra left off is not asked for again on every tap`() {
        // "Access past data" declined, background access allowed: the state
        // in which Health Connect raised its past-data sheet on each tap.
        assertFalse(mustAsk(importReads + readBackground))
        assertFalse(mustAsk(importReads + readHistory))
        assertFalse(mustAsk(importReads + readHistory + readBackground))
    }

    @Test
    fun `no write permission, granted or not, changes whether Import asks`() {
        assertFalse(mustAsk(importReads + writes))
        assertTrue(mustAsk(writes))
        assertTrue(mustAsk(writes + readHistory + readBackground))
    }

    @Test
    fun `a missing record read is asked for`() {
        assertTrue(mustAsk(emptySet()))
        assertTrue(mustAsk(setOf(readMenstruation)))
        assertTrue(mustAsk(setOf(readSpotting)))
        // The extras alone read nothing.
        assertTrue(mustAsk(setOf(readHistory, readBackground)))
    }

    @Test
    fun `Import asks exactly when the import status is not granted`() {
        for (granted in listOf(
            emptySet(),
            importReads,
            setOf(readMenstruation),
            writes,
            requested,
            importReads + readHistory,
            setOf(readHistory, readBackground),
        )) {
            for (everRequested in listOf(false, true)) {
                assertEquals(
                    importStatus(granted, everRequested) != "granted",
                    mustAsk(granted),
                )
            }
        }
    }
}
