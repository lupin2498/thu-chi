package vn.sothuchi.so_thu_chi.capture

import android.app.Application
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.os.Looper
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowSettings
import java.time.Duration

/** Kiểm thử luồng native: thông báo -> lưu giao dịch chờ -> cửa sổ ghi nhanh / thông báo nhắc. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class CaptureFlowTest {
    private val app: Application get() = RuntimeEnvironment.getApplication()

    private val mbTitle = "Thông báo biến động số dư"
    private val mbText = "TK 0xxx6789|GD: -150,000VND 22/10/26 16:30 |SD: 2,345,678VND|ND: NGUYEN VAN A chuyen tien"

    /** Gmail báo lại cùng giao dịch: tiêu đề = người gửi, nội dung = tiêu đề thư + trích đoạn. */
    private val gmail = "com.google.android.gm"
    private val mailSender = "MB Bank"
    private val mailText = "Thông báo biến động số dư\nKính gửi Quý khách, tài khoản 0xxx6789 vừa phát sinh giao dịch: " +
        "-150,000 VND. Nội dung: NGUYEN VAN A chuyen tien"

    private val prefs get() = app.getSharedPreferences("sothuchi_capture", Context.MODE_PRIVATE)

    @Before
    fun reset() {
        app.getSharedPreferences("sothuchi_capture", Context.MODE_PRIVATE).edit().clear().commit()
        ShadowSettings.setCanDrawOverlays(false)
    }

    private fun idle(ms: Long) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(ms))
    }

    private fun notifications(): List<Notification> {
        val nm = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return shadowOf(nm).allNotifications
    }

    @Test
    fun processStoresCaptureWithRealNulls() {
        val r = CaptureProcessor.process(app, "com.mbmobile", mbTitle, mbText, strict = false, present = false)
        assertTrue(r is CaptureProcessor.Outcome.Captured)
        val pending = CaptureStore.pending(app)
        assertEquals(1, pending.size)
        val m = CaptureStore.toMap(pending[0])
        assertEquals(150000L, m["amount"])
        assertEquals(false, m["income"])
        assertEquals("mbbank", m["bankKey"])
        assertEquals(2345678L, m["balance"])
        assertTrue((m["content"] as String).contains("NGUYEN VAN A"))

        // Thông báo không có nội dung / ngân hàng -> giá trị null thật, không phải chuỗi "null".
        val o = JSONObject().put("id", "x").put("amount", 1).put("content", JSONObject.NULL)
            .put("bankKey", JSONObject.NULL).put("balance", JSONObject.NULL)
        val m2 = CaptureStore.toMap(o)
        assertNull(m2["content"])
        assertNull(m2["bankKey"])
        assertNull(m2["balance"])
    }

    @Test
    fun dedupeAcrossSourcesButNotSameSource() {
        CaptureProcessor.process(app, "com.mbmobile", mbTitle, mbText, strict = false, present = false)
        // Ngân hàng đăng lại cùng thông báo.
        assertEquals(
            CaptureProcessor.Outcome.Duplicate,
            CaptureProcessor.process(app, "com.mbmobile", mbTitle, mbText, strict = false, present = false),
        )
        // SMS của cùng giao dịch.
        assertEquals(
            CaptureProcessor.Outcome.Duplicate,
            CaptureProcessor.process(
                app, "com.google.android.apps.messaging", "MBBank",
                "TK 0xxx6789|GD: -150,000VND 22/10/26 16:30 |SD: 2,345,678VND|ND: x", strict = true, present = false,
            ),
        )
        // Giao dịch thứ hai cùng số tiền trên cùng app -> vẫn ghi.
        val second = CaptureProcessor.process(
            app, "com.mbmobile", mbTitle,
            "TK 0xxx6789|GD: -150,000VND 22/10/26 16:31 |SD: 2,195,678VND|ND: tra tien com", strict = false, present = false,
        )
        assertTrue(second is CaptureProcessor.Outcome.Captured)
        assertEquals(2, CaptureStore.pending(app).size)
    }

    @Test
    fun gmailRepeatAfterBankIsFilteredAndRestorable() {
        val t = System.currentTimeMillis()
        val first = CaptureProcessor.process(app, "com.mbmobile", mbTitle, mbText, strict = false, present = false, now = t)
        val firstId = (first as CaptureProcessor.Outcome.Captured).id
        // 5 phút sau Gmail báo lại: cùng số tiền, cùng nội dung.
        assertEquals(
            CaptureProcessor.Outcome.Duplicate,
            CaptureProcessor.process(app, gmail, mailSender, mailText, strict = true, present = false, now = t + 5 * 60_000),
        )
        assertEquals(1, CaptureStore.pending(app).size)

        val filtered = CaptureStore.filtered(app)
        assertEquals(1, filtered.size)
        val m = CaptureStore.filteredToMap(filtered[0])
        assertEquals(150000L, m["amount"])
        assertEquals(gmail, m["packageName"])
        assertEquals("content", m["reason"])
        assertEquals(firstId, m["originalId"])
        assertEquals("com.mbmobile", m["originalPackage"])
        assertEquals(t, m["originalTime"])

        // Lọc nhầm -> đưa lại vào danh sách chờ ghi, bỏ phần ghi chú "trùng với...".
        val id = m["id"] as String
        val restored = CaptureStore.restoreFiltered(app, id)
        assertNotNull(restored)
        assertFalse(restored!!.has("dupReason"))
        assertFalse(restored.has("dupOfId"))
        assertEquals(2, CaptureStore.pending(app).size)
        assertNotNull(CaptureStore.get(app, id))
        assertTrue(CaptureStore.filtered(app).isEmpty())
        assertNull(CaptureStore.restoreFiltered(app, id))
        assertNull(CaptureStore.restoreFiltered(app, null))
    }

    @Test
    fun gmailRepeatHoursLaterStillFiltered() {
        val t = System.currentTimeMillis()
        CaptureProcessor.process(app, "com.mbmobile", mbTitle, mbText, strict = false, present = false, now = t)
        assertEquals(
            CaptureProcessor.Outcome.Duplicate,
            CaptureProcessor.process(app, gmail, mailSender, mailText, strict = true, present = false, now = t + 6 * 3_600_000L),
        )
        // Hôm sau có giao dịch mới cùng số tiền, cùng nội dung -> thư của nó không bị coi là trùng với hôm trước.
        assertTrue(
            CaptureProcessor.process(
                app, gmail, mailSender, mailText, strict = true, present = false, now = t + 26 * 3_600_000L,
            ) is CaptureProcessor.Outcome.Captured,
        )
        assertEquals(2, CaptureStore.pending(app).size)
    }

    @Test
    fun repostedNotificationIsDroppedSilently() {
        CaptureProcessor.process(app, "com.mbmobile", mbTitle, mbText, strict = false, present = false)
        assertEquals(
            CaptureProcessor.Outcome.Duplicate,
            CaptureProcessor.process(app, "com.mbmobile", mbTitle, mbText, strict = false, present = false),
        )
        // Thông báo đăng lại y nguyên không đưa vào danh sách "đã lọc".
        assertTrue(CaptureStore.filtered(app).isEmpty())
        assertEquals(1, CaptureStore.pending(app).size)
    }

    @Test
    fun filterTurnedOffKeepsOtherChannels() {
        CaptureStore.saveSettings(app, CaptureStore.Settings(dedupe = false))
        val t = System.currentTimeMillis()
        CaptureProcessor.process(app, "com.mbmobile", mbTitle, mbText, strict = false, present = false, now = t)
        assertTrue(
            CaptureProcessor.process(
                app, gmail, mailSender, mailText, strict = true, present = false, now = t + 60_000,
            ) is CaptureProcessor.Outcome.Captured,
        )
        assertEquals(2, CaptureStore.pending(app).size)
        assertTrue(CaptureStore.filtered(app).isEmpty())
        // Đúng thông báo đó được đăng lại thì vẫn bỏ.
        assertEquals(
            CaptureProcessor.Outcome.Duplicate,
            CaptureProcessor.process(app, "com.mbmobile", mbTitle, mbText, strict = false, present = false, now = t + 120_000),
        )
    }

    @Test
    fun duplicateDoesNotOpenPopupOrNotify() {
        ShadowSettings.setCanDrawOverlays(true)
        val t = System.currentTimeMillis()
        val r = CaptureProcessor.process(app, "com.mbmobile", mbTitle, mbText, strict = false, now = t)
        idle(400)
        assertNotNull(shadowOf(app).nextStartedActivity)
        CapturePresenter.onPopupShown(app, (r as CaptureProcessor.Outcome.Captured).id)
        assertEquals(
            CaptureProcessor.Outcome.Duplicate,
            CaptureProcessor.process(app, gmail, mailSender, mailText, strict = true, now = t + 60_000),
        )
        idle(4000)
        assertNull(shadowOf(app).nextStartedActivity)
        assertTrue(notifications().isEmpty())
    }

    @Test
    fun filteredListIsCapped() {
        repeat(25) { CaptureStore.addFiltered(app, JSONObject().put("id", "f$it").put("amount", 1000 + it)) }
        val list = CaptureStore.filtered(app)
        assertEquals(20, list.size)
        assertEquals("f5", list.first().getString("id"))
        assertEquals("f24", list.last().getString("id"))
        CaptureStore.clearFiltered(app)
        assertTrue(CaptureStore.filtered(app).isEmpty())
    }

    @Test
    fun oldAndCorruptedStoresAreHandled() {
        // Dấu vết chống trùng của bản 1.0.x bị xoá; dữ liệu hỏng không làm sập dịch vụ.
        prefs.edit()
            .putString("recent_keys", "[{\"t\":1,\"amount\":\"150000|false\",\"text\":\"1\",\"src\":\"x\"}]")
            .putString("seen_v2", "###")
            .putString("filtered", "{")
            .putString("pending", "không phải json")
            .commit()
        assertTrue(CaptureStore.filtered(app).isEmpty())
        assertTrue(CaptureStore.pending(app).isEmpty())
        val r = CaptureProcessor.process(app, "com.mbmobile", mbTitle, mbText, strict = false, present = false)
        assertTrue(r is CaptureProcessor.Outcome.Captured)
        assertEquals(1, CaptureStore.pending(app).size)
        assertFalse(prefs.contains("recent_keys"))
        assertTrue(prefs.getString("seen_v2", "")!!.startsWith("["))
    }

    @Test
    fun disabledSettingsIgnoresEverything() {
        CaptureStore.saveSettings(app, CaptureStore.Settings(enabled = false))
        assertEquals(
            CaptureProcessor.Outcome.Disabled,
            CaptureProcessor.process(app, "com.mbmobile", mbTitle, mbText, strict = false, present = false),
        )
        assertTrue(CaptureStore.pending(app).isEmpty())
    }

    @Test
    fun settingsRoundTrip() {
        val s = CaptureStore.Settings(
            enabled = true, disabledBanks = setOf("vcb"), readSms = false, anyApp = true,
            extraPackages = listOf("a.b"), showPopup = false, dedupe = false,
        )
        CaptureStore.saveSettings(app, s)
        assertEquals(s, CaptureStore.settings(app))
        assertEquals(s, CaptureStore.Settings.fromMap(s.toMap()))
        // Cài đặt lưu từ bản cũ (chưa có "dedupe") -> mặc định bật lọc trùng.
        prefs.edit().putString("settings", "{\"enabled\":true,\"anyApp\":true}").commit()
        assertTrue(CaptureStore.settings(app).dedupe)
        assertTrue(CaptureStore.Settings.fromMap(mapOf("enabled" to true)).dedupe)
    }

    @Test
    fun removeAndClear() {
        CaptureProcessor.process(app, "com.mbmobile", mbTitle, mbText, strict = false, present = false)
        val id = CaptureStore.pending(app)[0].getString("id")
        assertNotNull(CaptureStore.get(app, id))
        CaptureStore.remove(app, id)
        assertNull(CaptureStore.get(app, id))
        CaptureProcessor.process(app, "com.mbmobile", mbTitle, mbText, strict = false, dedupe = false, present = false)
        CaptureStore.clear(app)
        assertTrue(CaptureStore.pending(app).isEmpty())
    }

    @Test
    fun overlayGrantedLaunchesQuickAddActivity() {
        ShadowSettings.setCanDrawOverlays(true)
        val r = CaptureProcessor.process(app, "com.mbmobile", mbTitle, mbText, strict = false)
        val id = (r as CaptureProcessor.Outcome.Captured).id
        idle(400)
        val started = shadowOf(app).nextStartedActivity
        assertNotNull(started)
        assertEquals(QuickAddActivity::class.java.name, started.component?.className)
        assertEquals(id, started.getStringExtra(CapturePresenter.EXTRA_CAPTURE_ID))
        assertTrue(started.flags and android.content.Intent.FLAG_ACTIVITY_NEW_TASK != 0)

        // Cửa sổ không hiện (máy chặn) -> sau 3 giây chuyển sang thông báo nhắc.
        idle(3000)
        assertEquals(1, notifications().size)
    }

    @Test
    fun overlayShownPopupSkipsReminder() {
        ShadowSettings.setCanDrawOverlays(true)
        val r = CaptureProcessor.process(app, "com.mbmobile", mbTitle, mbText, strict = false)
        val id = (r as CaptureProcessor.Outcome.Captured).id
        idle(400)
        CapturePresenter.onPopupShown(app, id)
        idle(3000)
        assertTrue(notifications().isEmpty())
    }

    @Test
    fun notificationIdStableAndPositive() {
        val a = CapturePresenter.notificationId("abc")
        assertEquals(a, CapturePresenter.notificationId("abc"))
        assertTrue(a >= 7000)
        assertTrue(CapturePresenter.formatMoney(1500000).startsWith("1.500.000"))
    }
}
