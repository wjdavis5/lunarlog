package com.wjdavis5.lunarlog

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Issue #1564: a changes page carries only the records that changed, and
 * Dart takes the heaviest flow it is given for a day. A lighter record
 * added to a day that already had a heavier one made the day lighter. The
 * adapter now reads the whole of every day a changes page touches; these
 * pin which day a record falls on and what is read to see that day whole.
 */
class HealthTouchedDaysTest {

    private fun day(iso: String): LocalDate = LocalDate.parse(iso)

    @Test
    fun `a record falls on the day its own offset puts it on`() {
        // 03:30 UTC on the 11th is still the 10th four hours west of it.
        val time = Instant.parse("2026-09-11T03:30:00Z")
        assertEquals(
            day("2026-09-10"),
            HealthTouchedDays.dateOf(time, ZoneOffset.ofHours(-4)),
        )
        assertEquals(
            day("2026-09-11"),
            HealthTouchedDays.dateOf(time, ZoneOffset.UTC),
        )
        // And 21:00 UTC on the 10th is already the 11th nine hours east.
        assertEquals(
            day("2026-09-11"),
            HealthTouchedDays.dateOf(
                Instant.parse("2026-09-10T21:00:00Z"),
                ZoneOffset.ofHours(9),
            ),
        )
    }

    @Test
    fun `a record with no offset falls on no day`() {
        assertNull(
            HealthTouchedDays.dateOf(Instant.parse("2026-09-11T03:30:00Z"), null),
        )
    }

    @Test
    fun `no touched day means nothing to read`() {
        assertEquals(
            emptyList<Pair<Instant, Instant>>(),
            HealthTouchedDays.windows(emptySet()),
        )
    }

    @Test
    fun `one day is read from before it can begin to after it can end`() {
        val window = HealthTouchedDays.windows(setOf(day("2026-09-10"))).single()
        // The day begins earliest at offset +18:00 and ends latest at -18:00.
        assertEquals(Instant.parse("2026-09-09T06:00:00Z"), window.first)
        assertEquals(Instant.parse("2026-09-11T18:00:00Z"), window.second)
    }

    @Test
    fun `the window holds a record on that day under any offset`() {
        val date = day("2026-09-10")
        val window = HealthTouchedDays.windows(setOf(date)).single()
        for (hours in -18..18) {
            val offset = ZoneOffset.ofHours(hours)
            val first = date.atStartOfDay().toInstant(offset)
            val last = date.plusDays(1).atStartOfDay().toInstant(offset).minusMillis(1)
            for (time in listOf(first, last)) {
                assertEquals(date, HealthTouchedDays.dateOf(time, offset))
                assertTrue(
                    "offset $hours: $time is outside $window",
                    !time.isBefore(window.first) && !time.isAfter(window.second),
                )
            }
        }
    }

    @Test
    fun `days close together are read in one request`() {
        val windows = HealthTouchedDays.windows(
            setOf(day("2026-09-10"), day("2026-09-12"), day("2026-10-13")),
        )
        // The 12th of September to the 13th of October is 31 days.
        assertEquals(1, windows.size)
        assertEquals(Instant.parse("2026-09-09T06:00:00Z"), windows.single().first)
        assertEquals(Instant.parse("2026-10-14T18:00:00Z"), windows.single().second)
    }

    @Test
    fun `days far apart are read apart, in date order`() {
        val windows = HealthTouchedDays.windows(
            setOf(day("2026-10-14"), day("2026-09-10"), day("2026-09-12")),
        )
        // The 12th of September to the 14th of October is 32 days.
        assertEquals(
            listOf(
                Instant.parse("2026-09-09T06:00:00Z") to
                    Instant.parse("2026-09-13T18:00:00Z"),
                Instant.parse("2026-10-13T06:00:00Z") to
                    Instant.parse("2026-10-15T18:00:00Z"),
            ),
            windows,
        )
    }

    @Test
    fun `the gap is measured from the last day of a run, not its first`() {
        // Each step is 31 days, so all three share one request although the
        // first and the last are 62 days apart.
        val windows = HealthTouchedDays.windows(
            setOf(day("2026-01-01"), day("2026-02-01"), day("2026-03-04")),
        )
        assertEquals(1, windows.size)
        assertEquals(Instant.parse("2025-12-31T06:00:00Z"), windows.single().first)
        assertEquals(Instant.parse("2026-03-05T18:00:00Z"), windows.single().second)
    }
}
