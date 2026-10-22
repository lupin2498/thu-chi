package vn.sothuchi.so_thu_chi.capture

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.util.UUID

/** Phân tích nội dung thông báo -> lưu giao dịch chờ -> bật cửa sổ ghi nhanh. */
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
    ): Outcome {
        val settings = CaptureStore.settings(ctx)
        if (!settings.enabled) return Outcome.Disabled
        val r = BankParser.parse(text, title, packageName, strict) ?: return Outcome.Ignored
        val now = System.currentTimeMillis()
        if (dedupe) {
            val amountKey = "${r.amount}|${r.isIncome}"
            val textKey = "${packageName.orEmpty()}|${title.orEmpty()}|$text".hashCode().toString()
            if (CaptureStore.checkAndRemember(ctx, amountKey, textKey, packageName.orEmpty(), now)) {
                Log.d(TAG, "Bỏ qua giao dịch trùng ${r.amount}")
                return Outcome.Duplicate
            }
        }
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
        CaptureStore.add(ctx, capture)
        Log.i(TAG, "Bắt được giao dịch ${if (r.isIncome) "+" else "-"}${r.amount} từ $packageName")
        if (present) CapturePresenter.present(ctx, capture, settings.showPopup)
        return Outcome.Captured(id)
    }
}
