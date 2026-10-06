package com.wjdavis5.lunarlog

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Issue #1594: a record deleted in the app it came from was never reported
 * to Dart, so its imported day stayed in lunarlog. These pin what a page of
 * changes reports, and when a page request starts a whole-range read.
 */
class HealthChangeFoldTest {

    @Test
    fun `a written record is a record and is not deleted`() {
        val fold = HealthChangeFold<String>()
        fold.upsert("a", "light")
        assertEquals(listOf("light"), fold.records.toList())
        assertEquals(emptyList<String>(), fold.deletedIds)
    }

    @Test
    fun `a deleted record is reported by its id and has no record`() {
        val fold = HealthChangeFold<String>()
        fold.delete("a")
        assertEquals(emptyList<String>(), fold.records.toList())
        assertEquals(listOf("a"), fold.deletedIds)
    }

    @Test
    fun `written and then deleted is gone`() {
        val fold = HealthChangeFold<String>()
        fold.upsert("a", "light")
        fold.delete("a")
        assertEquals(emptyList<String>(), fold.records.toList())
        assertEquals(listOf("a"), fold.deletedIds)
    }

    @Test
    fun `deleted and then written again is there, with the later value`() {
        val fold = HealthChangeFold<String>()
        fold.upsert("a", "light")
        fold.delete("a")
        fold.upsert("a", "heavy")
        assertEquals(listOf("heavy"), fold.records.toList())
        assertEquals(emptyList<String>(), fold.deletedIds)
    }

    @Test
    fun `each id is settled on its own, in the order first seen`() {
        val fold = HealthChangeFold<String>()
        fold.upsert("a", "light")
        fold.delete("b")
        fold.upsert("c", "medium")
        fold.delete("d")
        fold.delete("b")
        assertEquals(listOf("light", "medium"), fold.records.toList())
        assertEquals(listOf("b", "d"), fold.deletedIds)
    }

    @Test
    fun `only the first page of a pass starts over, and only when asked`() {
        assertTrue(HealthImportCursor.startsOver(hasCursor = false, wholeHistory = true))
        assertFalse(HealthImportCursor.startsOver(hasCursor = true, wholeHistory = true))
        assertFalse(HealthImportCursor.startsOver(hasCursor = false, wholeHistory = false))
        assertFalse(HealthImportCursor.startsOver(hasCursor = true, wholeHistory = false))
    }
}
