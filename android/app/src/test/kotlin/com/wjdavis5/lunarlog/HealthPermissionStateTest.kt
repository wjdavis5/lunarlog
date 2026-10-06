package com.wjdavis5.lunarlog

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Issues #1478 and #1515: pins the `permissionStatus` decision the Android
 * adapter reports to Dart — may lunarlog write?
 *
 * Two things were wrong before #1478. A fresh install answered "denied"
 * before the person had been asked anything, because Android cannot tell
 * "never asked" from "denied" by looking at what is granted — and since the
 * Dart write pass stops on "denied" before its own authorization request,
 * the Android write path could never ask. And the status required every
 * requested permission but the background read, so declining an optional
 * READ permission (Health Connect's "Access past data") reported "denied"
 * and blocked every write.
 *
 * #1515 gave the import a permission request of its own, for the reads
 * alone. So "asked" has to mean asked for the WRITES: a read granted on the
 * import's sheet is no evidence that a write permission was ever shown, and
 * answering "denied" for it would put the write path back in the trap
 * above.
 */
class HealthPermissionStateTest {

    private val writeMenstruation = "android.permission.health.WRITE_MENSTRUATION"
    private val writeSpotting =
        "android.permission.health.WRITE_INTERMENSTRUAL_BLEEDING"
    private val readMenstruation = "android.permission.health.READ_MENSTRUATION"
    private val readSpotting =
        "android.permission.health.READ_INTERMENSTRUAL_BLEEDING"
    private val readHistory = "android.permission.health.READ_HEALTH_DATA_HISTORY"
    private val readBackground =
        "android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND"

    /** What `permissionStatus` is decided on: the write permissions only. */
    private val writes = setOf(writeMenstruation, writeSpotting)

    /** What the import's own request asks for: the reads, and no write. */
    private val importRequest =
        setOf(readMenstruation, readSpotting, readHistory, readBackground)

    /** What the write path's request asks for: writes and reads together. */
    private val writeRequest = writes + importRequest

    private fun status(granted: Set<String>, writesEverRequested: Boolean): String =
        HealthPermissionState.writeStatusFor(
            granted = granted,
            writes = writes,
            writesEverRequested = writesEverRequested,
        )

    @Test
    fun `a fresh install is not asked yet, never denied`() {
        assertEquals("notAsked", status(emptySet(), writesEverRequested = false))
    }

    @Test
    fun `once the write request has been launched, nothing granted is denied`() {
        assertEquals("denied", status(emptySet(), writesEverRequested = true))
    }

    @Test
    fun `every write permission granted is granted`() {
        assertEquals("granted", status(writes, writesEverRequested = true))
    }

    @Test
    fun `granted does not depend on the remembered flag`() {
        // Granted in Health Connect's own settings, or by a build that asked
        // before the flag existed.
        assertEquals("granted", status(writes, writesEverRequested = false))
    }

    @Test
    fun `declining the read permissions does not deny the writes`() {
        // The person allowed every write and left "Access past data", the
        // background read, and the reads themselves off.
        assertEquals("granted", status(writes, writesEverRequested = true))
        assertEquals(
            "granted",
            status(writes + readMenstruation, writesEverRequested = true),
        )
    }

    @Test
    fun `a missing write permission reports writingSome when at least one write is granted`() {
        assertEquals(
            "writingSome",
            status(setOf(writeMenstruation) + importRequest, writesEverRequested = true),
        )
    }

    @Test
    fun `one write granted reports writingSome, flag or no flag`() {
        // A write switched on in Health Connect's settings, or on the sheet
        // of a build older than the flag: partial write access reports writingSome.
        assertEquals(
            "writingSome",
            status(setOf(writeMenstruation), writesEverRequested = false),
        )
        assertEquals(
            "writingSome",
            status(setOf(writeMenstruation), writesEverRequested = true),
        )
    }

    // Issue #1515. Before it, any granted permission proved "asked", which
    // was true while one request carried everything. The import's request
    // carries the reads alone.
    @Test
    fun `reads allowed on the import sheet do not prove she was asked for the writes`() {
        // She tapped Import and allowed everything it asked for. No write
        // permission has ever been shown to her.
        assertEquals("notAsked", status(importRequest, writesEverRequested = false))
        assertEquals(
            "notAsked",
            status(setOf(readMenstruation, readSpotting), writesEverRequested = false),
        )
        assertEquals("notAsked", status(setOf(readHistory), writesEverRequested = false))
        assertEquals("notAsked", status(setOf(readBackground), writesEverRequested = false))
    }

    @Test
    fun `reads on, and the writes asked for and declined, is denied`() {
        // The person the issue is about: the write path's sheet was shown,
        // she allowed the reads on it and not the writes.
        assertEquals("denied", status(importRequest, writesEverRequested = true))
        assertEquals(
            "denied",
            status(setOf(readMenstruation, readSpotting), writesEverRequested = true),
        )
    }

    @Test
    fun `a permission the app does not request proves nothing`() {
        assertEquals(
            "notAsked",
            status(
                setOf("android.permission.health.READ_STEPS"),
                writesEverRequested = false,
            ),
        )
    }

    // The review of Issue #1478: access granted without this install's own
    // sheet (an older build's, or Health Connect's settings) and later
    // removed altogether must read "denied", not "not yet asked" — with a
    // forward-only cursor in place the write pass never asks again, so
    // "not yet asked" would leave every write failing with no Settings
    // link. The adapter sets the write marker whenever provesAsked is true
    // over the WRITE permissions, which turns the later revocation into
    // writesEverRequested = true.
    @Test
    fun `a write grant is what the adapter remembers as asked for the writes`() {
        assertTrue(HealthPermissionState.provesAsked(writes, writes))
        assertTrue(HealthPermissionState.provesAsked(setOf(writeSpotting), writes))
        assertTrue(
            HealthPermissionState.provesAsked(setOf(writeSpotting) + importRequest, writes),
        )
    }

    private fun remembers(granted: Set<String>, importRequestLaunched: Boolean): Boolean =
        HealthPermissionState.remembersWritesAsked(
            granted = granted,
            writes = writes,
            requested = writeRequest,
            importRequestLaunched = importRequestLaunched,
        )

    @Test
    fun `a read granted on the import's own sheet is not remembered as asked for the writes`() {
        // Issue #1515: remembering it would make the write status read
        // "denied" for someone who has only ever tapped Import, and the
        // write pass would stop before its own request.
        assertFalse(remembers(importRequest, importRequestLaunched = true))
        assertFalse(remembers(setOf(readMenstruation), importRequestLaunched = true))
        assertFalse(remembers(setOf(readBackground), importRequestLaunched = true))
        // A read grant is still no write grant.
        assertFalse(HealthPermissionState.provesAsked(importRequest, writes))
    }

    @Test
    fun `a read granted before the import had its own request is remembered as asked`() {
        // The review of Issue #1515. An install from before the asked-marker
        // existed has no marker. Someone who allowed the reads and declined
        // the writes on that build's single sheet was asked for the writes,
        // and the only evidence left is the granted read. Until this install
        // launches the import's own request, no sheet can have offered a
        // read without the writes beside it.
        assertTrue(remembers(setOf(readMenstruation, readSpotting), importRequestLaunched = false))
        assertTrue(remembers(setOf(readHistory), importRequestLaunched = false))
        assertTrue(remembers(importRequest, importRequestLaunched = false))
    }

    @Test
    fun `that upgrade reads denied, so the write sheet is not raised for her again`() {
        // What the adapter does with it: it sets the write marker on the
        // first look, and the status is then decided with the marker set.
        val readsOnly = setOf(readMenstruation, readSpotting)
        assertTrue(remembers(readsOnly, importRequestLaunched = false))
        assertEquals("denied", status(readsOnly, writesEverRequested = true))
        // Without the rule she would read "notAsked", and the write pass
        // asks on "notAsked".
        assertEquals("notAsked", status(readsOnly, writesEverRequested = false))
    }

    @Test
    fun `a write grant is remembered whichever requests have been launched`() {
        for (importRequestLaunched in listOf(false, true)) {
            assertTrue(remembers(setOf(writeSpotting), importRequestLaunched))
            assertTrue(remembers(writeRequest, importRequestLaunched))
        }
    }

    @Test
    fun `nothing granted, or something the app never requests, is never remembered`() {
        for (importRequestLaunched in listOf(false, true)) {
            assertFalse(remembers(emptySet(), importRequestLaunched))
            assertFalse(
                remembers(
                    setOf("android.permission.health.READ_STEPS"),
                    importRequestLaunched,
                ),
            )
        }
    }

    @Test
    fun `nothing granted, or only something the app never requests, proves nothing`() {
        assertFalse(HealthPermissionState.provesAsked(emptySet(), writes))
        assertFalse(HealthPermissionState.provesAsked(emptySet(), writeRequest))
        assertFalse(
            HealthPermissionState.provesAsked(
                setOf("android.permission.health.READ_STEPS"),
                writeRequest,
            ),
        )
    }

    @Test
    fun `write access seen granted and then removed altogether reads denied`() {
        // While granted, the adapter sees provesAsked and sets the marker...
        assertTrue(HealthPermissionState.provesAsked(writes, writes))
        assertEquals("granted", status(writes, writesEverRequested = false))
        // ...so once everything is revoked the marker answers for it.
        assertEquals("denied", status(emptySet(), writesEverRequested = true))
    }

    @Test
    fun `the write status decision reports granted, writingSome, denied, or notAsked`() {
        // All writes granted -> granted regardless of writesEverRequested
        assertEquals("granted", status(writes, writesEverRequested = false))
        assertEquals("granted", status(writes, writesEverRequested = true))
        assertEquals("granted", status(writeRequest, writesEverRequested = true))

        // Some writes granted -> writingSome regardless of writesEverRequested
        assertEquals("writingSome", status(setOf(writeMenstruation), writesEverRequested = false))
        assertEquals("writingSome", status(setOf(writeMenstruation), writesEverRequested = true))
        assertEquals("writingSome", status(setOf(writeSpotting), writesEverRequested = false))
        assertEquals("writingSome", status(setOf(writeSpotting), writesEverRequested = true))

        // 0 writes granted -> denied if asked, notAsked if not asked
        assertEquals("denied", status(emptySet(), writesEverRequested = true))
        assertEquals("denied", status(importRequest, writesEverRequested = true))
        assertEquals("notAsked", status(emptySet(), writesEverRequested = false))
        assertEquals("notAsked", status(importRequest, writesEverRequested = false))
    }

    // Issue #1573: the request for "Access past data" alone.
    @Test
    fun `past data is asked for only when both record reads are granted`() {
        val reads = setOf(readMenstruation, readSpotting)
        assertTrue(HealthPermissionState.pastDataMayAsk(reads, reads))
        assertTrue(HealthPermissionState.pastDataMayAsk(reads + writes, reads))
        assertFalse(HealthPermissionState.pastDataMayAsk(setOf(readMenstruation), reads))
        assertFalse(HealthPermissionState.pastDataMayAsk(emptySet(), reads))
        assertFalse(HealthPermissionState.pastDataMayAsk(writes, reads))
    }

    // With no read granted and neither request launched, a grant of past
    // data alone would read as proof that the write sheet had been shown.
    // The rule above is what keeps the request from being raised then.
    @Test
    fun `a past data grant alone would mark the writes as asked, which is why it is never asked for alone`() {
        val requested = writes + setOf(readMenstruation, readSpotting, readHistory)
        assertTrue(
            HealthPermissionState.remembersWritesAsked(
                granted = setOf(readHistory),
                writes = writes,
                requested = requested,
                importRequestLaunched = false,
            ),
        )
        assertFalse(
            HealthPermissionState.pastDataMayAsk(
                emptySet(),
                setOf(readMenstruation, readSpotting),
            ),
        )
        // With the record reads granted the answer was already yes, so the
        // grant changes nothing.
        val before = setOf(readMenstruation, readSpotting)
        for (launched in listOf(false, true)) {
            assertEquals(
                HealthPermissionState.remembersWritesAsked(before, writes, requested, launched),
                HealthPermissionState.remembersWritesAsked(
                    before + readHistory, writes, requested, launched,
                ),
            )
        }
    }

    @Test
    fun `the import's sheet carries past data only when neither sheet has been raised before`() {
        val reads = setOf(readHistory, readMenstruation, readSpotting, readBackground)
        val pastData = setOf(readHistory)
        assertEquals(
            reads,
            HealthPermissionState.importRequestPermissions(reads, pastData, launchedBefore = false),
        )
        assertEquals(
            setOf(readMenstruation, readSpotting, readBackground),
            HealthPermissionState.importRequestPermissions(reads, pastData, launchedBefore = true),
        )
        // A phone with no such switch has nothing to leave out.
        val noSwitch = reads - readHistory
        assertEquals(
            noSwitch,
            HealthPermissionState.importRequestPermissions(noSwitch, emptySet(), launchedBefore = true),
        )
    }

    @Test
    fun `the wire strings are the Dart HealthPermissionStatus names`() {
        assertEquals("granted", HealthPermissionState.GRANTED)
        assertEquals("notAsked", HealthPermissionState.NOT_ASKED)
        assertEquals("denied", HealthPermissionState.DENIED)
        assertEquals("writingSome", HealthPermissionState.WRITING_SOME)
    }
}
