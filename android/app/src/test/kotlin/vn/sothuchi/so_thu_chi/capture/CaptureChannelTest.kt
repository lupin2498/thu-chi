package vn.sothuchi.so_thu_chi.capture

import android.app.Activity
import android.app.Application
import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.nio.ByteBuffer

/** Kênh vn.sothuchi/capture: các lệnh Dart gọi sang (cài đặt, danh sách chờ, danh sách đã lọc trùng). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class CaptureChannelTest {
    private val app: Application get() = RuntimeEnvironment.getApplication()

    private val mbTitle = "Thông báo biến động số dư"
    private val mbText = "TK 0xxx6789|GD: -150,000VND 22/10/26 16:30 |SD: 2,345,678VND|ND: NGUYEN VAN A chuyen tien"
    private val mailText = "Thông báo biến động số dư\nGiao dịch: -150,000 VND. Nội dung: NGUYEN VAN A chuyen tien"

    private class FakeMessenger : BinaryMessenger {
        override fun send(channel: String, message: ByteBuffer?) {}
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {}
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {}
    }

    private class Reply : MethodChannel.Result {
        var value: Any? = null
        var errorCode: String? = null
        var missing = false
        var answered = 0

        override fun success(result: Any?) {
            value = result
            answered++
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            this.errorCode = errorCode
            answered++
        }

        override fun notImplemented() {
            missing = true
            answered++
        }
    }

    private lateinit var handler: CaptureChannelHandler

    @Before
    fun setUp() {
        app.getSharedPreferences("sothuchi_capture", Context.MODE_PRIVATE).edit().clear().commit()
        val activity = Robolectric.buildActivity(Activity::class.java).get()
        handler = CaptureChannelHandler(activity, FakeMessenger())
    }

    private fun call(method: String, args: Any? = null): Reply {
        val reply = Reply()
        handler.onMethodCall(MethodCall(method, args), reply)
        assertEquals("$method phải trả lời đúng một lần", 1, reply.answered)
        assertNull("$method lỗi", reply.errorCode)
        return reply
    }

    @Suppress("UNCHECKED_CAST")
    private fun list(method: String): List<Map<String, Any?>> = call(method).value as List<Map<String, Any?>>

    @Test
    fun settingsIncludeDedupeSwitch() {
        @Suppress("UNCHECKED_CAST")
        val defaults = call("getSettings").value as Map<String, Any?>
        assertEquals(true, defaults["dedupe"])
        call("setSettings", defaults + mapOf("dedupe" to false, "anyApp" to true))
        val saved = CaptureStore.settings(app)
        assertFalse(saved.dedupe)
        assertTrue(saved.anyApp)
        // Bản Dart cũ không gửi "dedupe" -> giữ mặc định bật.
        call("setSettings", mapOf("enabled" to true))
        assertTrue(CaptureStore.settings(app).dedupe)
    }

    @Test
    fun filteredCapturesListRestoreClear() {
        assertTrue(list("getFilteredCaptures").isEmpty())
        val t = System.currentTimeMillis()
        CaptureProcessor.process(app, "com.mbmobile", mbTitle, mbText, strict = false, present = false, now = t)
        CaptureProcessor.process(app, "com.google.android.gm", "MB Bank", mailText, strict = true, present = false, now = t + 60_000)

        val filtered = list("getFilteredCaptures")
        assertEquals(1, filtered.size)
        val f = filtered[0]
        assertEquals(150000L, f["amount"])
        assertEquals(false, f["income"])
        assertEquals("com.google.android.gm", f["packageName"])
        assertEquals("content", f["reason"])
        assertEquals("com.mbmobile", f["originalPackage"])
        assertEquals(t, f["originalTime"])
        assertEquals(1, list("getPendingCaptures").size)

        // Mã không tồn tại / thiếu mã -> null, không lỗi.
        assertNull(call("restoreFiltered", mapOf("id" to "không có")).value)
        assertNull(call("restoreFiltered", emptyMap<String, Any>()).value)

        @Suppress("UNCHECKED_CAST")
        val restored = call("restoreFiltered", mapOf("id" to f["id"])).value as Map<String, Any?>
        assertEquals(f["id"], restored["id"])
        assertEquals(150000L, restored["amount"])
        assertFalse(restored.containsKey("reason"))
        assertEquals(2, list("getPendingCaptures").size)
        assertTrue(list("getFilteredCaptures").isEmpty())

        // Ghi xong giao dịch vừa khôi phục -> xoá khỏi danh sách chờ.
        call("removeCapture", mapOf("id" to f["id"]))
        assertEquals(1, list("getPendingCaptures").size)

        CaptureStore.addFiltered(app, org.json.JSONObject().put("id", "x").put("amount", 5000))
        assertEquals(1, list("getFilteredCaptures").size)
        call("clearFiltered")
        assertTrue(list("getFilteredCaptures").isEmpty())
    }

    @Test
    fun unknownMethodAndSimulation() {
        val reply = Reply()
        handler.onMethodCall(MethodCall("khongCoLenhNay", null), reply)
        assertTrue(reply.missing)

        assertEquals("ignored", call("simulateNotification", mapOf("title" to "MB Bank", "text" to "Chào bạn")).value)
        assertEquals("scheduled", call("simulateNotification", mapOf("title" to mbTitle, "text" to mbText)).value)
        CaptureStore.saveSettings(app, CaptureStore.Settings(enabled = false))
        assertEquals("disabled", call("simulateNotification", mapOf("title" to mbTitle, "text" to mbText)).value)

        @Suppress("UNCHECKED_CAST")
        val perms = call("getPermissions").value as Map<String, Boolean>
        assertEquals(vn.sothuchi.so_thu_chi.BuildConfig.NOTIFICATION_CAPTURE, perms["notificationCapture"])
        assertEquals(false, perms["overlay"])
    }
}
