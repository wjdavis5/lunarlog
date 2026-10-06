package com.wjdavis5.lunarlog

import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * When the home-screen widget next has to redraw: just after the next local
 * midnight (issue #1548).
 *
 * The widget shows a cycle-day count, which changes at midnight. The
 * system's own periodic update runs every 24 hours counted from when the
 * widget was placed, so its time of day is arbitrary: a widget placed at
 * 3 pm kept showing the previous day's number from midnight until 3 pm
 * unless the app happened to be opened.
 *
 * Kept free of Android types so it can be unit tested on the JVM.
 */
object WidgetMidnight {
    /**
     * How far past midnight the redraw is asked for, so that it lands on
     * the new day and not on its first instant.
     */
    val AFTER_MIDNIGHT: Duration = Duration.ofSeconds(5)

    /**
     * Epoch milliseconds of the next redraw after [now]: the start of the
     * next day in [zone], plus [AFTER_MIDNIGHT].
     *
     * "The start of the day" and not "00:00": in a zone whose clocks go
     * forward at midnight, that day starts at 01:00.
     */
    fun nextRefreshMillis(now: Instant, zone: ZoneId): Long =
        ZonedDateTime.ofInstant(now, zone)
            .toLocalDate()
            .plusDays(1)
            .atStartOfDay(zone)
            .plus(AFTER_MIDNIGHT)
            .toInstant()
            .toEpochMilli()
}
