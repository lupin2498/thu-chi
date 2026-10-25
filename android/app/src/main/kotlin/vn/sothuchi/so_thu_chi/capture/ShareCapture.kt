package vn.sothuchi.so_thu_chi.capture

import org.json.JSONObject
import java.util.UUID

/** Tạo giao dịch chờ từ nội dung người dùng "Chia sẻ" sang (ảnh biên lai / chữ). */
object ShareCapture {
    fun build(lines: List<ReceiptParser.Line>, packageName: String?, now: Long = System.currentTimeMillis()): JSONObject {
        val r = ReceiptParser.parse(lines, packageName)
        val raw = lines.joinToString("\n") { it.text }.let { if (it.length > 2000) it.substring(0, 2000) else it }
        return JSONObject()
            .put("id", UUID.randomUUID().toString())
            .put("amount", r?.amount ?: 0L)
            .put("income", r?.isIncome ?: false)
            .put("bankKey", r?.bankKey ?: JSONObject.NULL)
            .put("content", r?.content ?: JSONObject.NULL)
            .put("rawText", raw.ifEmpty { JSONObject.NULL })
            .put("packageName", packageName ?: JSONObject.NULL)
            .put("balance", JSONObject.NULL)
            .put("time", now)
            .put("source", "share")
    }
}
