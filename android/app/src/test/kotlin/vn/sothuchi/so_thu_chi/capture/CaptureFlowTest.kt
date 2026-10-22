package vn.sothuchi.so_thu_chi.capture

import android.app.Application
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.os.Bundle
import android.os.Looper
import android.os.Process
import android.os.UserHandle
import android.service.notification.StatusBarNotification
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
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
            extraPackages = listOf("a.b"), showPopup = false,
        )
        CaptureStore.saveSettings(app, s)
        assertEquals(s, CaptureStore.settings(app))
        assertEquals(s, CaptureStore.Settings.fromMap(s.toMap()))
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
    fun extractTextPrefersBigTextAndLatestMessage() {
        val b = Bundle()
        b.putCharSequence(Notification.EXTRA_TITLE, "MB Bank")
        b.putCharSequence(Notification.EXTRA_TEXT, "TK 0xxx|GD: -150,000VND…")
        b.putCharSequence(Notification.EXTRA_BIG_TEXT, mbText)
        val (title, body) = BankNotificationListener.extractText(b)
        assertEquals("MB Bank", title)
        assertEquals(mbText, body)

        val sms = Bundle()
        sms.putCharSequence(Notification.EXTRA_TITLE, "MBBank")
        sms.putCharSequence(Notification.EXTRA_TEXT, "2 tin nhắn mới")
        val m1 = Bundle().apply { putCharSequence("text", "tin cũ") }
        val m2 = Bundle().apply { putCharSequence("text", "TK 0xxx|GD: -50,000VND|SD: 1,000VND") }
        sms.putParcelableArray(Notification.EXTRA_MESSAGES, arrayOf(m1, m2))
        assertEquals("TK 0xxx|GD: -50,000VND|SD: 1,000VND", BankNotificationListener.extractText(sms).second)
    }

    @Suppress("DEPRECATION")
    private fun sbn(pkg: String, title: String, text: String, ongoing: Boolean = false): StatusBarNotification {
        val n = Notification.Builder(app, "x")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setOngoing(ongoing)
            .build()
        return StatusBarNotification(
            pkg, pkg, 1, null, Process.myUid(), 0, 0, n, UserHandle.getUserHandleForUid(Process.myUid()), System.currentTimeMillis(),
        )
    }

    @Test
    fun listenerFiltersPackagesAndPostsReminderWithoutOverlay() {
        val service = Robolectric.setupService(BankNotificationListener::class.java)
        service.onNotificationPosted(sbn("com.zing.zalo", "Bạn A", "chuyển tao 200k"))
        service.onNotificationPosted(sbn("com.google.android.apps.messaging", "Mẹ", "mua thịt hết 300.000đ"))
        service.onNotificationPosted(sbn("com.mbmobile", mbTitle, mbText, ongoing = true))
        assertTrue(CaptureStore.pending(app).isEmpty())

        service.onNotificationPosted(sbn("com.mbmobile", mbTitle, mbText))
        assertEquals(1, CaptureStore.pending(app).size)
        // Chưa có quyền hiển thị trên app khác -> thông báo nhắc có nút "Ghi chép".
        val posted = notifications()
        assertEquals(1, posted.size)
        assertNotNull(posted[0].contentIntent)
        assertTrue(posted[0].extras.getCharSequence(Notification.EXTRA_TITLE).toString().contains("150.000"))

        // Tắt ngân hàng MB -> bỏ qua.
        CaptureStore.saveSettings(app, CaptureStore.Settings(disabledBanks = setOf("mbbank")))
        service.onNotificationPosted(
            sbn("com.mbmobile", mbTitle, "TK 0xxx6789|GD: -99,000VND 22/10/26 17:00 |SD: 1,000VND|ND: x"),
        )
        assertEquals(1, CaptureStore.pending(app).size)

        // SMS ngân hàng (chế độ chặt) vẫn nhận.
        service.onNotificationPosted(
            sbn("com.google.android.apps.messaging", "VCB", "Số dư TK VCB 0011001234567 -75,000 VND lúc 22-10-2026 11:30:00. Số dư 1,000,000 VND. Ref ca phe"),
        )
        assertEquals(2, CaptureStore.pending(app).size)
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
