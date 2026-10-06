package com.wjdavis5.lunarlog

import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import org.junit.Assert.assertEquals
import org.junit.Test

/** Issue #1548: the widget redraws just after the next local midnight. */
class WidgetMidnightTest {
    private val newYork = ZoneId.of("America/New_York")

    private fun at(text: String): Instant = ZonedDateTime.parse(text).toInstant()

    private fun next(now: String, zone: ZoneId): ZonedDateTime =
        Instant.ofEpochMilli(WidgetMidnight.nextRefreshMillis(at(now), zone)).atZone(zone)

    @Test
    fun `in the afternoon it is the coming midnight`() {
        assertEquals(
            ZonedDateTime.parse("2026-10-06T00:00:05-04:00[America/New_York]"),
            next("2026-10-05T15:00:00-04:00[America/New_York]", newYork),
        )
    }

    @Test
    fun `a second before midnight it is that midnight`() {
        assertEquals(
            ZonedDateTime.parse("2026-10-06T00:00:05-04:00[America/New_York]"),
            next("2026-10-05T23:59:59-04:00[America/New_York]", newYork),
        )
    }

    @Test
    fun `at midnight it is the next one, a day on`() {
        // A redraw at midnight already shows the new day; the one to ask
        // for is tomorrow's, not one five seconds away.
        assertEquals(
            ZonedDateTime.parse("2026-10-07T00:00:05-04:00[America/New_York]"),
            next("2026-10-06T00:00:00-04:00[America/New_York]", newYork),
        )
        assertEquals(
            ZonedDateTime.parse("2026-10-07T00:00:05-04:00[America/New_York]"),
            next("2026-10-06T00:00:03-04:00[America/New_York]", newYork),
        )
    }

    @Test
    fun `it is always in the future, and never more than a long day away`() {
        val now = at("2026-10-05T15:00:00-04:00[America/New_York]")
        var instant = now
        repeat(400) {
            val refresh = Instant.ofEpochMilli(
                WidgetMidnight.nextRefreshMillis(instant, newYork),
            )
            assert(refresh.isAfter(instant)) { "$refresh is not after $instant" }
            // 25 hours is the day the clocks go back.
            assert(refresh.isBefore(instant.plusSeconds(25 * 3600 + 6))) {
                "$refresh is more than a day after $instant"
            }
            instant = instant.plusSeconds(23 * 3600 + 1800)
        }
    }

    @Test
    fun `the day the clocks go back is 25 hours long`() {
        // 1 November 2026 in New York.
        assertEquals(
            ZonedDateTime.parse("2026-11-01T00:00:05-04:00[America/New_York]"),
            next("2026-10-31T22:00:00-04:00[America/New_York]", newYork),
        )
        assertEquals(
            ZonedDateTime.parse("2026-11-02T00:00:05-05:00[America/New_York]"),
            next("2026-11-01T12:00:00-05:00[America/New_York]", newYork),
        )
    }

    @Test
    fun `where the clocks go forward at midnight, the day starts at one`() {
        // Sao Paulo, 4 November 2018: 00:00 did not happen.
        val saoPaulo = ZoneId.of("America/Sao_Paulo")
        assertEquals(
            ZonedDateTime.parse("2018-11-04T01:00:05-02:00[America/Sao_Paulo]"),
            next("2018-11-03T12:00:00-03:00[America/Sao_Paulo]", saoPaulo),
        )
    }

    @Test
    fun `it is the phone's midnight, not UTC's`() {
        val kiritimati = ZoneId.of("Pacific/Kiritimati")
        val now = "2026-10-05T23:30:00+14:00[Pacific/Kiritimati]"
        assertEquals(
            ZonedDateTime.parse("2026-10-06T00:00:05+14:00[Pacific/Kiritimati]"),
            next(now, kiritimati),
        )
        // The same instant in New York is the morning of the 5th.
        assertEquals(
            ZonedDateTime.parse("2026-10-06T00:00:05-04:00[America/New_York]"),
            next(now, newYork),
        )
    }
}
