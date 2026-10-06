package com.wjdavis5.lunarlog

import androidx.health.connect.client.records.CervicalMucusRecord
import androidx.health.connect.client.records.MenstruationFlowRecord
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/**
 * Issue #1583: pins that a SecurityException for one type does not produce
 * a plain allowed response, but reports which types were skipped.
 */
class HealthDeletionStateTest {

    @Test
    fun `when all types succeed it produces allowed`() {
        val result = HealthDeletionState.deleteRecords(
            listOf(MenstruationFlowRecord::class, CervicalMucusRecord::class)
        ) { /* success */ }
        assertEquals("allowed", result)
    }

    @Test
    fun `a SecurityException for one type does not produce a plain allowed`() {
        val result = HealthDeletionState.deleteRecords(
            listOf(MenstruationFlowRecord::class, CervicalMucusRecord::class)
        ) { type ->
            if (type == CervicalMucusRecord::class) throw SecurityException("denied")
        }
        assertNotEquals("allowed", result)
        assertEquals(
            mapOf("status" to "partial", "skippedTypes" to listOf("cervicalMucus")),
            result
        )
    }
}
