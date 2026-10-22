package vn.sothuchi.so_thu_chi.capture

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DedupeTest {
    private val t0 = 1_000_000_000L

    @Test
    fun sameTextIsDuplicateWithinTenMinutes() {
        val (d1, r1) = CaptureStore.dedupe(emptyList(), "150000|false", "h1", "com.mbmobile", t0)
        assertFalse(d1)
        val (d2, _) = CaptureStore.dedupe(r1, "150000|false", "h1", "com.mbmobile", t0 + 5 * 60_000)
        assertTrue(d2)
        val (d3, _) = CaptureStore.dedupe(r1, "150000|false", "h1", "com.mbmobile", t0 + 11 * 60_000)
        assertFalse(d3)
    }

    @Test
    fun sameAmountSameSourceIsNotDuplicate() {
        val (_, r1) = CaptureStore.dedupe(emptyList(), "50000|false", "a", "com.mbmobile", t0)
        val (d2, r2) = CaptureStore.dedupe(r1, "50000|false", "b", "com.mbmobile", t0 + 20_000)
        assertFalse(d2)
        assertEquals(2, r2.size)
    }

    @Test
    fun sameAmountOtherSourceWithin90sIsDuplicate() {
        val (_, r1) = CaptureStore.dedupe(emptyList(), "50000|false", "a", "com.mbmobile", t0)
        val (d2, _) = CaptureStore.dedupe(r1, "50000|false", "sms", "com.google.android.apps.messaging", t0 + 30_000)
        assertTrue(d2)
        val (d3, _) = CaptureStore.dedupe(r1, "50000|false", "sms", "com.google.android.apps.messaging", t0 + 120_000)
        assertFalse(d3)
        val (d4, _) = CaptureStore.dedupe(r1, "50000|true", "sms", "com.google.android.apps.messaging", t0 + 30_000)
        assertFalse(d4)
    }

    @Test
    fun oldEntriesArePruned() {
        val (_, r1) = CaptureStore.dedupe(emptyList(), "1|false", "a", "x", t0)
        val (_, r2) = CaptureStore.dedupe(r1, "2|false", "b", "x", t0 + 20 * 60_000)
        assertEquals(1, r2.size)
        // Đồng hồ bị lùi: bỏ mục ở tương lai.
        val (_, r3) = CaptureStore.dedupe(r2, "3|false", "c", "x", t0)
        assertEquals(1, r3.size)
    }
}
