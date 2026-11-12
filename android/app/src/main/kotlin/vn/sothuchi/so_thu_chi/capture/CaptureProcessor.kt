package vn.sothuchi.so_thu_chi.capture

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.util.UUID

/** Phân tích nội dung thông báo -> lọc trùng -> lưu giao dịch chờ -> bật cửa sổ ghi nhanh. */
object CaptureProcessor {
    private const val TAG = "SoThuChiCapture"

    sealed class Outcome {
        data class Captured(val id: String) : Outcome()
        object Ignored : Outcome()
        object Duplicate : Outcome()
        object Disabled : Outcome()
    }

    fun process(
        ctx: Context,
        packageName: String?,
        title: String?,
        text: String,
        strict: Boolean,
        postTime: Long = System.currentTimeMillis(),
        dedupe: Boolean = true,
        present: Boolean = true,
        now: Long = System.currentTimeMillis(),
    ): Outcome {
        val settings = CaptureStore.settings(ctx)
        if (!settings.enabled) return Outcome.Disabled
        val r = BankParser.parse(text, title, packageName, strict) ?: return Outcome.Ignored
        val id = UUID.randomUUID().toString()
        val raw = listOfNotNull(title?.takeIf { it.isNotBlank() }, text).joinToString("\n")
        val capture = JSONObject()
            .put("id", id)
            .put("amount", r.amount)
            .put("income", r.isIncome)
            .put("bankKey", r.bankKey ?: JSONObject.NULL)
            .put("content", r.content ?: JSONObject.NULL)
            .put("rawText", raw)
            .put("packageName", packageName ?: JSONObject.NULL)
            .put("balance", r.balance ?: JSONObject.NULL)
            .put("time", if (postTime > 0) postTime else now)
        if (dedupe) {
            val sig = CaptureDedupe.signature(r, packageName, title, text)
            val match = CaptureStore.checkDuplicate(ctx, sig, id, now, crossCheck = settings.dedupe)
            if (match != null) {
                Log.d(TAG, "Bỏ qua thông báo trùng ${r.amount} (${match.reason.key}) từ $packageName")
                // Thông báo đăng lại y nguyên không cần giữ; trùng do kênh khác báo lại thì lưu để xem lại được.
                if (match.reason != CaptureDedupe.Reason.REPOST) {
                    CaptureStore.addFiltered(
                        ctx,
                        capture
                            .put("dupReason", match.reason.key)
                            .put("dupOfId", match.seen.id)
                            .put("dupOfTime", match.seen.t)
                            .put("dupOfPackage", match.seen.sources.firstOrNull()?.substringBefore('|') ?: JSONObject.NULL),
                    )
                }
                return Outcome.Duplicate
            }
        }
        CaptureStore.add(ctx, capture)
        Log.i(TAG, "Bắt được giao dịch ${if (r.isIncome) "+" else "-"}${r.amount} từ $packageName")
        if (present) CapturePresenter.present(ctx, capture, settings.showPopup)
        return Outcome.Captured(id)
    }
}
