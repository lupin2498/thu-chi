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
    private const val KEY_SEEN = "seen_v2"
    private const val KEY_FILTERED = "filtered"
    private const val KEY_LAST_SHOWN = "last_shown"
    private const val MAX_PENDING = 50
    private const val MAX_FILTERED = 20

    /** Dấu vết chống trùng của bản 1.0.x (không còn dùng). */
    private const val KEY_RECENT_LEGACY = "recent_keys"

    /** Thông tin "trùng với giao dịch nào" gắn thêm vào thông báo đã lọc. */
    private val filterKeys = listOf("dupReason", "dupOfId", "dupOfTime", "dupOfPackage")

    data class Settings(
        val enabled: Boolean = true,
        val disabledBanks: Set<String> = emptySet(),
        val readSms: Boolean = true,
        val anyApp: Boolean = false,
        val extraPackages: List<String> = emptyList(),
        val showPopup: Boolean = true,
        /** Lọc thông báo trùng: kênh khác (Gmail, SMS...) báo lại cùng số tiền + nội dung thì bỏ qua. */
        val dedupe: Boolean = true,
    ) {
        fun toMap(): Map<String, Any> = mapOf(
            "enabled" to enabled,
            "disabledBanks" to disabledBanks.toList(),
            "readSms" to readSms,
            "anyApp" to anyApp,
            "extraPackages" to extraPackages,
            "showPopup" to showPopup,
            "dedupe" to dedupe,
        )

        companion object {
            fun fromMap(m: Map<*, *>): Settings = Settings(
                enabled = m["enabled"] as? Boolean ?: true,
                disabledBanks = (m["disabledBanks"] as? List<*>)?.mapNotNull { it?.toString() }?.toSet() ?: emptySet(),
                readSms = m["readSms"] as? Boolean ?: true,
                anyApp = m["anyApp"] as? Boolean ?: false,
                extraPackages = (m["extraPackages"] as? List<*>)?.mapNotNull { it?.toString() } ?: emptyList(),
                showPopup = m["showPopup"] as? Boolean ?: true,
                dedupe = m["dedupe"] as? Boolean ?: true,
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
                dedupe = o.optBoolean("dedupe", true),
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
        o.put("dedupe", s.dedupe)
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

    /**
     * Kiểm tra thông báo có phải báo lại của một giao dịch đã ghi nhận gần đây không
     * (xem [CaptureDedupe]); chưa có thì ghi nhận dấu vết với mã [id].
     * [crossCheck] = false: chỉ lọc đúng thông báo được đăng lại.
     */
    @Synchronized
    fun checkDuplicate(
        ctx: Context,
        sig: CaptureDedupe.Signature,
        id: String,
        now: Long,
        crossCheck: Boolean,
    ): CaptureDedupe.Match? {
        val p = prefs(ctx)
        val outcome = CaptureDedupe.check(CaptureDedupe.decode(p.getString(KEY_SEEN, null)), sig, id, now, crossCheck)
        p.edit().putString(KEY_SEEN, CaptureDedupe.encode(outcome.seen)).remove(KEY_RECENT_LEGACY).apply()
        return outcome.match
    }

    // ------------------------------------------ Thông báo trùng đã lọc bỏ

    /** Các thông báo vừa bị lọc vì trùng (mới nhất ở cuối) để người dùng xem lại / ghi lại nếu lọc nhầm. */
    @Synchronized
    fun filtered(ctx: Context): List<JSONObject> {
        val raw = prefs(ctx).getString(KEY_FILTERED, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).mapNotNull { arr.optJSONObject(it) }
        } catch (e: Exception) {
            emptyList()
        }
    }

    @Synchronized
    fun addFiltered(ctx: Context, capture: JSONObject) {
        val list = filtered(ctx).toMutableList()
        list.add(capture)
        while (list.size > MAX_FILTERED) list.removeAt(0)
        writeFiltered(ctx, list)
    }

    /** Đưa thông báo đã lọc trở lại danh sách chờ ghi; trả về giao dịch đó (null nếu không còn). */
    @Synchronized
    fun restoreFiltered(ctx: Context, id: String?): JSONObject? {
        if (id == null) return null
        val list = filtered(ctx)
        val capture = list.firstOrNull { it.optString("id") == id } ?: return null
        writeFiltered(ctx, list.filterNot { it.optString("id") == id })
        for (key in filterKeys) capture.remove(key)
        add(ctx, capture)
        return capture
    }

    @Synchronized
    fun clearFiltered(ctx: Context) {
        writeFiltered(ctx, emptyList())
    }

    private fun writeFiltered(ctx: Context, list: List<JSONObject>) {
        val arr = JSONArray()
        list.forEach { arr.put(it) }
        prefs(ctx).edit().putString(KEY_FILTERED, arr.toString()).commit()
    }

    fun filteredToMap(o: JSONObject): Map<String, Any?> {
        val m = HashMap(toMap(o))
        m["reason"] = o.str("dupReason")
        m["originalId"] = o.str("dupOfId")
        m["originalTime"] = if (o.has("dupOfTime") && !o.isNull("dupOfTime")) o.optLong("dupOfTime") else null
        m["originalPackage"] = o.str("dupOfPackage")
        return m
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
