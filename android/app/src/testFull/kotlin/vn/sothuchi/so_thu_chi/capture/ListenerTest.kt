package vn.sothuchi.so_thu_chi.capture

import android.app.Application
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.os.Bundle
import android.os.Process
import android.os.UserHandle
import android.service.notification.StatusBarNotification
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
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

/** Kiểm thử dịch vụ đọc thông báo (chỉ có trong bản "full"). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ListenerTest {
    private val app: Application get() = RuntimeEnvironment.getApplication()

    private val mbTitle = "Thông báo biến động số dư"
    private val mbText = "TK 0xxx6789|GD: -150,000VND 22/10/26 16:30 |SD: 2,345,678VND|ND: NGUYEN VAN A chuyen tien"

    @Before
    fun reset() {
        app.getSharedPreferences("sothuchi_capture", Context.MODE_PRIVATE).edit().clear().commit()
        ShadowSettings.setCanDrawOverlays(false)
    }

    private fun notifications(): List<Notification> {
        val nm = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return shadowOf(nm).allNotifications
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
    fun gmailRepeatOfBankNotificationIsFiltered() {
        val service = Robolectric.setupService(BankNotificationListener::class.java)
        val mail = "Thông báo biến động số dư\nKính gửi Quý khách, tài khoản 0xxx6789 vừa phát sinh giao dịch: " +
            "-150,000 VND. Nội dung: NGUYEN VAN A chuyen tien"

        // Chưa bật "Mọi ứng dụng": thông báo Gmail không được đọc.
        service.onNotificationPosted(sbn("com.google.android.gm", "MB Bank", mail))
        assertTrue(CaptureStore.pending(app).isEmpty())

        CaptureStore.saveSettings(app, CaptureStore.Settings(anyApp = true))
        service.onNotificationPosted(sbn("com.mbmobile", mbTitle, mbText))
        assertEquals(1, CaptureStore.pending(app).size)
        assertEquals(1, notifications().size)

        // Ngân hàng báo xong, Gmail báo lại cùng số tiền + nội dung -> không ghi nhận lần nữa.
        service.onNotificationPosted(sbn("com.google.android.gm", "MB Bank", mail))
        assertEquals(1, CaptureStore.pending(app).size)
        assertEquals(1, notifications().size)
        val filtered = CaptureStore.filtered(app)
        assertEquals(1, filtered.size)
        assertEquals("content", filtered[0].getString("dupReason"))
        assertEquals("com.mbmobile", filtered[0].getString("dupOfPackage"))

        // Gmail đăng lại đúng thông báo đó (gộp thư) -> vẫn bỏ, không thêm vào danh sách đã lọc.
        service.onNotificationPosted(sbn("com.google.android.gm", "MB Bank", mail))
        assertEquals(1, CaptureStore.pending(app).size)
        assertEquals(1, CaptureStore.filtered(app).size)

        // Giao dịch khác (số tiền khác) qua Gmail vẫn được ghi.
        service.onNotificationPosted(
            sbn("com.google.android.gm", "MB Bank", mail.replace("-150,000", "-275,000")),
        )
        assertEquals(2, CaptureStore.pending(app).size)

        // Tắt lọc trùng: thư báo lại của giao dịch mới được giữ.
        CaptureStore.saveSettings(app, CaptureStore.Settings(anyApp = true, dedupe = false))
        service.onNotificationPosted(
            sbn("com.mbmobile", mbTitle, "TK 0xxx6789|GD: -99,000VND 22/10/26 17:00 |SD: 1,000VND|ND: tien nuoc"),
        )
        service.onNotificationPosted(
            sbn("com.google.android.gm", "MB Bank", "Giao dịch: -99,000 VND. Nội dung: tien nuoc"),
        )
        assertEquals(4, CaptureStore.pending(app).size)
    }
}
