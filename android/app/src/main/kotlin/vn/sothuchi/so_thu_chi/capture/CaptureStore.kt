package vn.sothuchi.so_thu_chi.capture

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * Lưu cài đặt tự động ghi chép và các giao dịch bắt được đang chờ người dùng xác nhận.
 * Dùng SharedPreferences để dịch vụ đọc thông báo và cả hai Flutter engine cùng truy cập.
 */
object CaptureStore {
    private const val PREFS = "sothuchi_capture"
    private const val KEY_PENDING = "pending"
    private const val KEY_SETTINGS = "settings"
    private const val KEY_RECENT = "recent_keys"
    private const val KEY_LAST_SHOWN = "last_shown"
    private const val MAX_PENDING = 50

    /** Cùng số tiền & chiều từ hai nguồn khác nhau trong khoảng này coi là trùng (SMS + thông báo app). */
    const val SAME_AMOUNT_WINDOW_MS = 90_000L

    /** Cùng nội dung thông báo trong khoảng này coi là trùng (ngân hàng cập nhật lại thông báo). */
    const val SAME_TEXT_WINDOW_MS = 10 * 60_000L

    data class Settings(
        val enabled: Boolean = true,
        val disabledBanks: Set<String> = emptySet(),
        val readSms: Boolean = true,
        val anyApp: Boolean = false,
        val extraPackages: List<String> = emptyList(),
        val showPopup: Boolean = true,
    ) {
        fun toMap(): Map<String, Any> = mapOf(
            "enabled" to enabled,
            "disabledBanks" to disabledBanks.toList(),
            "readSms" to readSms,
            "anyApp" to anyApp,
            "extraPackages" to extraPackages,
            "showPopup" to showPopup,
        )

        companion object {
            fun fromMap(m: Map<*, *>): Settings = Settings(
                enabled = m["enabled"] as? Boolean ?: true,
                disabledBanks = (m["disabledBanks"] as? List<*>)?.mapNotNull { it?.toString() }?.toSet() ?: emptySet(),
                readSms = m["readSms"] as? Boolean ?: true,
                anyApp = m["anyApp"] as? Boolean ?: false,
                extraPackages = (m["extraPackages"] as? List<*>)?.mapNotNull { it?.toString() } ?: emptyList(),
                showPopup = m["showPopup"] as? Boolean ?: true,
            )
        }
    }

    private fun prefs(ctx: Context): SharedPreferences =
        ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // ------------------------------------------------------------- Cài đặt

    @Synchronized
    fun settings(ctx: Context): Settings {
        val raw = prefs(ctx).getString(KEY_SETTINGS, null) ?: return Settings()
        return try {
            val o = JSONObject(raw)
            Settings(
                enabled = o.optBoolean("enabled", true),
                disabledBanks = o.optJSONArray("disabledBanks").toStringList().toSet(),
                readSms = o.optBoolean("readSms", true),
                anyApp = o.optBoolean("anyApp", false),
                extraPackages = o.optJSONArray("extraPackages").toStringList(),
                showPopup = o.optBoolean("showPopup", true),
            )
        } catch (e: Exception) {
            Settings()
        }
    }

    @Synchronized
    fun saveSettings(ctx: Context, s: Settings) {
        val o = JSONObject()
        o.put("enabled", s.enabled)
        o.put("disabledBanks", JSONArray(s.disabledBanks.toList()))
        o.put("readSms", s.readSms)
        o.put("anyApp", s.anyApp)
        o.put("extraPackages", JSONArray(s.extraPackages))
        o.put("showPopup", s.showPopup)
        prefs(ctx).edit().putString(KEY_SETTINGS, o.toString()).apply()
    }

    // ------------------------------------------------- Giao dịch đang chờ

    @Synchronized
    fun pending(ctx: Context): List<JSONObject> {
        val raw = prefs(ctx).getString(KEY_PENDING, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).mapNotNull { arr.optJSONObject(it) }
        } catch (e: Exception) {
            emptyList()
        }
    }

    @Synchronized
    fun add(ctx: Context, capture: JSONObject) {
        val list = pending(ctx).toMutableList()
        list.removeAll { it.optString("id") == capture.optString("id") }
        list.add(capture)
        while (list.size > MAX_PENDING) list.removeAt(0)
        writePending(ctx, list)
    }

    @Synchronized
    fun get(ctx: Context, id: String?): JSONObject? {
        if (id == null) return null
        return pending(ctx).firstOrNull { it.optString("id") == id }
    }

    @Synchronized
    fun remove(ctx: Context, id: String) {
        val list = pending(ctx).filterNot { it.optString("id") == id }
        writePending(ctx, list)
    }

    @Synchronized
    fun clear(ctx: Context) {
        writePending(ctx, emptyList())
    }

    private fun writePending(ctx: Context, list: List<JSONObject>) {
        val arr = JSONArray()
        list.forEach { arr.put(it) }
        // commit() để popup (engine khác) đọc được ngay.
        prefs(ctx).edit().putString(KEY_PENDING, arr.toString()).commit()
    }

    // ---------------------------------------------------------- Chống trùng

    /** Dấu vết giao dịch gần đây để chống ghi trùng. */
    data class Recent(val t: Long, val amount: String, val text: String, val src: String)

    /**
     * Logic chống trùng (thuần, để unit test): trả về (trùng?, danh sách dấu vết mới).
     * - Cùng nội dung thông báo trong 10 phút -> trùng (ngân hàng đăng lại thông báo).
     * - Cùng số tiền & chiều từ nguồn KHÁC trong 90 giây -> trùng (SMS + app của cùng giao dịch).
     *   Cùng nguồn thì là hai giao dịch thật (vd chuyển 2 lần 50.000đ).
     */
    fun dedupe(recent: List<Recent>, amountKey: String, textKey: String, source: String, now: Long): Pair<Boolean, List<Recent>> {
        val kept = recent.filter { val age = now - it.t; age in 0..SAME_TEXT_WINDOW_MS }
        val dup = kept.any { r ->
            r.text == textKey ||
                (now - r.t <= SAME_AMOUNT_WINDOW_MS && r.amount == amountKey && r.src != source)
        }
        return dup to (if (dup) kept else kept + Recent(now, amountKey, textKey, source))
    }

    /** Trả true nếu giao dịch đã ghi nhận gần đây; nếu chưa thì ghi lại dấu vết. */
    @Synchronized
    fun checkAndRemember(ctx: Context, amountKey: String, textKey: String, source: String, now: Long): Boolean {
        val p = prefs(ctx)
        val recent = try {
            val arr = JSONArray(p.getString(KEY_RECENT, "[]"))
            (0 until arr.length()).mapNotNull { i ->
                arr.optJSONObject(i)?.let {
                    Recent(it.optLong("t"), it.optString("amount"), it.optString("text"), it.optString("src"))
                }
            }
        } catch (e: Exception) {
            emptyList()
        }
        val (dup, next) = dedupe(recent, amountKey, textKey, source, now)
        val out = JSONArray()
        next.forEach {
            out.put(JSONObject().put("t", it.t).put("amount", it.amount).put("text", it.text).put("src", it.src))
        }
        p.edit().putString(KEY_RECENT, out.toString()).apply()
        return dup
    }

    // -------------------------------------------- Theo dõi cửa sổ đã hiện

    @Synchronized
    fun markShown(ctx: Context, id: String?) {
        if (id == null) return
        prefs(ctx).edit().putString(KEY_LAST_SHOWN, id).apply()
    }

    @Synchronized
    fun lastShown(ctx: Context): String? = prefs(ctx).getString(KEY_LAST_SHOWN, null)

    fun toMap(o: JSONObject): Map<String, Any?> {
        val m = HashMap<String, Any?>()
        m["id"] = o.optString("id")
        m["amount"] = o.optLong("amount")
        m["income"] = o.optBoolean("income")
        m["bankKey"] = o.str("bankKey")
        m["content"] = o.str("content")
        m["rawText"] = o.str("rawText")
        m["packageName"] = o.str("packageName")
        m["balance"] = if (o.has("balance") && !o.isNull("balance")) o.optLong("balance") else null
        m["time"] = o.optLong("time")
        return m
    }

    /** optString trả "null" với JSONObject.NULL -> đổi thành null thật. */
    fun JSONObject.str(key: String): String? =
        if (!has(key) || isNull(key)) null else optString(key).ifEmpty { null }

    private fun JSONArray?.toStringList(): List<String> {
        if (this == null) return emptyList()
        return (0 until length()).mapNotNull { optString(it).ifEmpty { null } }
    }
}
