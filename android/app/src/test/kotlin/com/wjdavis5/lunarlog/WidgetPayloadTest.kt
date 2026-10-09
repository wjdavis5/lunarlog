package com.wjdavis5.lunarlog

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Issue #1731: the payload is one JSON envelope, so parsing reads every
 * documented field from that single entry; anything missing or malformed
 * reads as the neutral state.
 */
class WidgetPayloadTest {
    private val envelope = """
        {
          "ll_widget_state": "day",
          "ll_widget_cycle_day": "14",
          "ll_widget_days_until_next": "7",
          "ll_widget_can_quick_log": "1",
          "ll_widget_profile_id": "01JTESTPROFILE",
          "ll_widget_as_of": "2026-10-09"
        }
    """.trimIndent()

    @Test
    fun `parses every documented field`() {
        val payload = WidgetPayload.parse(envelope)
        assertEquals("day", payload?.state)
        assertEquals("14", payload?.cycleDay)
        assertEquals("7", payload?.daysUntilNext)
        assertEquals("1", payload?.canQuickLog)
        assertEquals("01JTESTPROFILE", payload?.profileId)
        assertEquals("2026-10-09", payload?.asOf)
    }

    @Test
    fun `a missing envelope parses to null`() {
        assertNull(WidgetPayload.parse(null))
        assertNull(WidgetPayload.parse(""))
        assertNull(WidgetPayload.parse("   "))
    }

    @Test
    fun `a malformed envelope parses to null`() {
        assertNull(WidgetPayload.parse("not json"))
        assertNull(WidgetPayload.parse("{\"ll_widget_state\":"))
    }

    @Test
    fun `an absent field reads as null, not as an error`() {
        val payload = WidgetPayload.parse("{\"ll_widget_state\":\"no_data\"}")
        assertEquals("no_data", payload?.state)
        assertNull(payload?.cycleDay)
        assertNull(payload?.daysUntilNext)
        assertNull(payload?.canQuickLog)
        assertNull(payload?.profileId)
        assertNull(payload?.asOf)
    }
}
