package vn.sothuchi.so_thu_chi.capture

import android.app.Notification
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

/**
 * Nhận thông báo của hệ thống; chỉ xử lý thông báo từ ứng dụng ngân hàng/ví/tin nhắn
 * (theo cài đặt) và chuyển nội dung cho [CaptureProcessor]. Không lưu thông báo nào khác.
 */
class BankNotificationListener : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        try {
            handle(sbn)
        } catch (t: Throwable) {
            Log.w("SoThuChiCapture", "Lỗi xử lý thông báo", t)
        }
    }

    private fun handle(sbn: StatusBarNotification) {
        val pkg = sbn.packageName ?: return
        if (pkg == packageName) return
        val n = sbn.notification ?: return
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        if (sbn.isOngoing) return

        val settings = CaptureStore.settings(this)
        if (!settings.enabled) return
        val bank = BankApps.byPackage(pkg)
        val strict: Boolean = when {
            bank != null -> {
                if (bank.key in settings.disabledBanks) return
                false
            }
            pkg in settings.extraPackages -> false
            pkg in BankApps.smsPackages -> {
                if (!settings.readSms) return
                true
            }
            settings.anyApp -> true
            else -> return
        }

        val (title, body) = extractText(n.extras ?: return)
        if (body.isBlank()) return
        CaptureProcessor.process(this, pkg, title, body, strict, sbn.postTime)
    }

    companion object {
        /** Lấy tiêu đề + nội dung đầy đủ nhất của thông báo. */
        fun extractText(extras: Bundle): Pair<String?, String> {
            val title = (extras.getCharSequence(Notification.EXTRA_TITLE_BIG)
                ?: extras.getCharSequence(Notification.EXTRA_TITLE))?.toString()
            val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
            val big = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
            val lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
                ?.joinToString("\n") { it.toString() }
            // Tin nhắn (MessagingStyle): lấy tin mới nhất.
            var lastMessage: String? = null
            @Suppress("DEPRECATION")
            val messages = extras.getParcelableArray(Notification.EXTRA_MESSAGES)
            if (messages != null && messages.isNotEmpty()) {
                val b = messages.last() as? Bundle
                lastMessage = b?.getCharSequence("text")?.toString()
            }
            val body = lastMessage?.takeIf { it.isNotBlank() }
                ?: listOfNotNull(big, text, lines).maxByOrNull { it.length }
                ?: ""
            return title to body
        }
    }
}
