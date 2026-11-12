package vn.sothuchi.so_thu_chi.capture

import org.json.JSONArray
import org.json.JSONObject

/**
 * Lọc thông báo trùng: một giao dịch thường được báo qua nhiều kênh (app ngân hàng báo xong,
 * Gmail / SMS báo lại lần nữa). So theo SỐ TIỀN + NỘI DUNG chuyển khoản; khi có thì dùng thêm
 * số dư sau giao dịch và giờ giao dịch để chắc chắn hơn.
 *
 * Nguyên tắc: mỗi kênh chỉ báo một giao dịch một lần. Vì vậy thông báo mới chỉ bị coi là trùng với
 * giao dịch mà kênh đó CHƯA báo; hai lần chuyển cùng số tiền, cùng nội dung trên cùng một app vẫn
 * là hai giao dịch.
 *
 * Thuần Kotlin (không phụ thuộc Android) để unit test trên JVM.
 */
object CaptureDedupe {

    /** Đăng lại đúng thông báo cũ khi nội dung không có giờ GD / số dư để phân biệt. */
    const val REPOST_WINDOW_MS = 10 * 60_000L

    /** Kênh khác báo lại: cùng số tiền + (cùng nội dung | cùng số dư | cùng giờ GD). */
    const val LONG_WINDOW_MS = 12 * 60 * 60_000L

    /** Kênh khác báo lại, cùng ngân hàng nhưng không so được nội dung (email đến chậm). */
    const val SAME_BANK_WINDOW_MS = 10 * 60_000L

    /** Kênh khác báo lại, chỉ biết cùng số tiền & chiều. */
    const val TIME_WINDOW_MS = 2 * 60_000L

    /** Cùng một kênh báo hai lần cho một giao dịch (hai dạng thông báo). */
    const val SAME_SOURCE_WINDOW_MS = 60_000L

    const val MAX_ENTRIES = 60

    // Độ mạnh của bằng chứng = Reason.ordinal * 10; hai mức xen giữa:
    /** Giờ GD lệch 1 phút giữa hai kênh: yếu hơn trùng giờ chính xác. */
    private const val NEAR_CLOCK_RANK = 35

    /** Thông báo y hệt nhưng không có giờ GD / số dư: yếu hơn mọi bằng chứng khác trừ "báo sát nhau". */
    private const val WEAK_REPOST_RANK = 38
    private const val MAX_TEXT = 500

    /** Nội dung ngắn hơn mức này không đủ để tìm trong thông báo của kênh khác. */
    private const val MIN_PHRASE = 6
    private const val MIN_CUT_PHRASE = 10
    private const val MAX_TEXTS = 3
    private const val MAX_KEYS = 8
    private const val MAX_CLOCKS = 6

    enum class Reason(val key: String) {
        /** Đúng thông báo đó được đăng lại. */
        REPOST("repost"),

        /** Cùng số tiền và cùng số dư sau giao dịch. */
        BALANCE("balance"),

        /** Cùng số tiền và cùng nội dung. */
        CONTENT("content"),

        /** Cùng số tiền và cùng giờ giao dịch. */
        CLOCK("clock"),

        /** Cùng số tiền, hai kênh báo sát nhau. */
        TIME("time"),
    }

    private enum class Rel { MATCH, MISMATCH, UNKNOWN }

    /** Đặc điểm nhận dạng của một thông báo giao dịch. */
    data class Signature(
        val amount: Long,
        val income: Boolean,
        /** Chiều thu/chi đọc được rõ ràng (dấu +/- hoặc từ khoá); nếu không thì không dùng để phân biệt. */
        val directionKnown: Boolean,
        val balance: Long?,
        /** Nội dung chuyển khoản đã chuẩn hoá; rỗng nếu không có hoặc chỉ gồm từ chung chung. */
        val content: String,
        /** Toàn bộ thông báo đã chuẩn hoá (cắt ngắn). */
        val text: String,
        /** Khoá nhận ra đúng thông báo này (gói + tiêu đề + nội dung). */
        val textKey: String,
        /** Nội dung có giờ GD hoặc số dư: thông báo giống hệt chắc chắn là cùng một giao dịch. */
        val strongText: Boolean,
        /** Các mốc giờ "HH:mm" xuất hiện trong thông báo. */
        val clocks: List<String>,
        /** Kênh báo: gói ứng dụng (+ người gửi với app tin nhắn / email). */
        val source: String,
        /** Mã ngân hàng khi thông báo đến từ chính app ngân hàng / ví. */
        val bankApp: String?,
        /** Mã ngân hàng suy ra (từ gói hoặc từ nội dung). */
        val bank: String?,
        /** Định danh của chính thông báo (khoá thông báo + thời điểm app đặt); null nếu không có. */
        val postKey: String? = null,
    )

    /** Một giao dịch đã ghi nhận gần đây cùng các kênh đã báo về nó. */
    data class Seen(
        val id: String,
        /** Lúc ghi nhận lần đầu. */
        val t: Long,
        /** Lần gần nhất có kênh báo về giao dịch này. */
        val last: Long,
        val amount: Long,
        val income: Boolean,
        val directionKnown: Boolean,
        val balance: Long?,
        val content: String,
        val texts: List<String>,
        /** Các thông báo đã gộp vào giao dịch này. */
        val posts: List<Post>,
        val clocks: List<String>,
        val sources: List<String>,
        val bankApp: String?,
        val bank: String?,
    )

    /** Một thông báo đã thấy: khoá nội dung, lúc thấy lần đầu, định danh thông báo (nếu có). */
    data class Post(val key: String, val t: Long, val notif: String? = null)

    data class Match(val seen: Seen, val reason: Reason)

    data class Outcome(val match: Match?, val seen: List<Seen>)

    // ------------------------------------------------------------ Chuẩn hoá

    private val combining = Regex("[\\u0300-\\u036f]")
    private val validClock = Regex("^([01]\\d|2[0-3]):[0-5]\\d$")
    private val clock = Regex("(?<![\\d:])([01]?\\d|2[0-3]):([0-5]\\d)(?::[0-5]\\d)?(?![\\d:])")

    /** Từ chỉ hành động chuyển/trả tiền, không giúp phân biệt giao dịch này với giao dịch khác. */
    private val genericTokens = setOf(
        "chuyen", "tien", "khoan", "ck", "thanh", "toan", "tt", "gd", "giao", "dich", "nap", "rut",
        "hoa", "don", "qr", "ma", "nd", "noi", "dung", "den", "tu", "toi", "cho", "cua", "tk", "stk",
        "so", "ngan", "hang", "bank", "vnd", "dong", "qua", "tai", "ref", "ft", "ibft", "napas",
        "nhan", "tra", "phi", "va",
    )

    /** Bỏ dấu, chữ thường, chỉ giữ chữ cái + chữ số, các từ cách nhau một khoảng trắng. */
    fun normalize(input: String): String {
        val folded = BankParser.fold(input.replace(combining, ""))
        val sb = StringBuilder(folded.length)
        var pendingSpace = false
        for (ch in folded) {
            if ((ch in 'a'..'z') || (ch in '0'..'9')) {
                if (pendingSpace && sb.isNotEmpty()) sb.append(' ')
                pendingSpace = false
                sb.append(ch)
            } else {
                pendingSpace = true
            }
        }
        return sb.toString()
    }

    private fun significantTokens(normalized: String): List<String> =
        normalized.split(' ').filter { it.length >= 2 && it !in genericTokens }

    /** Các mốc giờ "HH:mm" trong văn bản (bỏ giây). */
    fun clocksOf(raw: String): List<String> {
        val out = LinkedHashSet<String>()
        for (m in clock.findAll(raw)) {
            out.add(m.groupValues[1].padStart(2, '0') + ":" + m.groupValues[2])
            if (out.size >= MAX_CLOCKS) break
        }
        return out.toList()
    }

    /** Kênh báo: app ngân hàng = tên gói; app tin nhắn / email = tên gói + người gửi. */
    fun sourceKey(packageName: String?, title: String?): String {
        val pkg = packageName.orEmpty()
        if (BankApps.byPackage(pkg) != null) return pkg
        val sender = normalize(title.orEmpty()).filter { it in 'a'..'z' }.take(40)
        return if (sender.isEmpty()) pkg else "$pkg|$sender"
    }

    /** FNV-1a 64 bit: khoá ổn định giữa các lần chạy (String.hashCode đủ dùng nhưng dễ trùng hơn). */
    private fun hash(s: String): String {
        var h = -0x340d631b7bdddcdbL // 0xcbf29ce484222325
        for (ch in s) {
            h = h xor ch.code.toLong()
            h *= 0x100000001b3L
        }
        return java.lang.Long.toHexString(h)
    }

    /**
     * [notificationKey]: khoá của thông báo trên hệ thống + thời điểm app đặt cho nó (Notification.when).
     * App đăng lại đúng thông báo cũ (Gmail cập nhật nhóm thư...) thì giữ nguyên hai giá trị này.
     */
    fun signature(
        r: BankParser.Result,
        packageName: String?,
        title: String?,
        text: String,
        notificationKey: String? = null,
    ): Signature {
        val raw = listOfNotNull(title?.trim()?.takeIf { it.isNotEmpty() }, text.trim()).joinToString("\n")
        val full = normalize(raw)
        var content = normalize(r.content.orEmpty())
        // Nội dung bị cắt ở 140 ký tự: từ cuối có thể dở dang.
        if (r.content?.endsWith("…") == true) content = content.substringBeforeLast(' ', "")
        if (significantTokens(content).isEmpty()) content = ""
        val clocks = clocksOf(raw)
        return Signature(
            amount = r.amount,
            income = r.isIncome,
            directionKnown = r.directionKnown,
            balance = r.balance,
            content = content,
            text = full.take(MAX_TEXT),
            textKey = hash(packageName.orEmpty() + "\n" + full) + ":" + full.length,
            strongText = clocks.isNotEmpty() || r.balance != null,
            clocks = clocks,
            source = sourceKey(packageName, title),
            bankApp = BankApps.byPackage(packageName)?.key,
            bank = r.bankKey,
            postKey = notificationKey?.let { hash(it) },
        )
    }

    // -------------------------------------------------------------- So khớp

    /**
     * [phrase] nằm trong một trong các [texts], bắt đầu ở đầu một từ. Cụm đủ dài được phép kết thúc
     * giữa chừng một từ vì trích đoạn email / thông báo hay bị cắt ngang.
     */
    private fun containsPhrase(texts: List<String>, phrase: String): Boolean {
        if (phrase.length < MIN_PHRASE) return false
        val partialEnd = phrase.length >= MIN_CUT_PHRASE
        return texts.any { if (partialEnd) " $it".contains(" $phrase") else " $it ".contains(" $phrase ") }
    }

    private fun contentRelation(s: Signature, r: Seen): Rel {
        val a = s.content
        val b = r.content
        if (a.isEmpty() && b.isEmpty()) return Rel.UNKNOWN
        // Nội dung của bên này nằm nguyên trong thông báo của bên kia (email / SMS chép lại nội dung CK).
        if (containsPhrase(listOf(s.text), b)) return Rel.MATCH
        if (containsPhrase(r.texts, a)) return Rel.MATCH
        if (a.isEmpty() || b.isEmpty()) return Rel.UNKNOWN
        val ta = significantTokens(a).toSet()
        val tb = significantTokens(b).toSet()
        val common = ta.intersect(tb).size
        val smaller = minOf(ta.size, tb.size)
        if (common == 0) return Rel.MISMATCH
        // Khác nhau chút ít do mỗi kênh thêm mã tham chiếu / cắt ngắn.
        if (common * 5 >= smaller * 4 && (common >= 2 || smaller == 1)) return Rel.MATCH
        return Rel.UNKNOWN
    }

    private fun clockRelation(a: List<String>, b: List<String>): Rel = when {
        a.isEmpty() || b.isEmpty() -> Rel.UNKNOWN
        a.any { it in b } -> Rel.MATCH
        else -> Rel.MISMATCH
    }

    private fun minutesOf(clock: String): Int =
        clock.substringBefore(':').toInt() * 60 + clock.substringAfter(':').toInt()

    /** Hai kênh ghi giờ GD lệch nhau tối đa 1 phút (mỗi kênh lấy mốc giờ ở một bước khác nhau). */
    private fun clocksNear(a: List<String>, b: List<String>): Boolean = a.any { x ->
        b.any { y ->
            val day = 24 * 60
            val d = ((minutesOf(x) - minutesOf(y)) % day + day) % day
            d <= 1 || d >= 24 * 60 - 1
        }
    }

    private fun bankRelation(a: String?, b: String?): Rel = when {
        a == null || b == null -> Rel.UNKNOWN
        a == b -> Rel.MATCH
        else -> Rel.MISMATCH
    }

    /** Bằng chứng trùng kèm độ mạnh (số nhỏ = chắc chắn hơn). */
    private class Evidence(val reason: Reason, val rank: Int)

    private fun strong(reason: Reason) = Evidence(reason, reason.ordinal * 10)

    /** Lý do coi thông báo [s] là báo lại của giao dịch [r]; null nếu là giao dịch khác. */
    private fun evidence(s: Signature, r: Seen, now: Long, crossCheck: Boolean): Evidence? {
        val sinceFirst = now - r.t
        val sinceLast = now - r.last
        if (sinceFirst < 0 || sinceLast < 0) return null

        val posted = r.posts.firstOrNull { it.key == s.textKey }
        if (posted != null) {
            val sameNotification = s.postKey != null && posted.notif == s.postKey
            return when {
                // Có giờ GD / số dư, hoặc đúng thông báo cũ được đăng lại (cùng định danh):
                // chắc chắn là cùng một giao dịch.
                s.strongText || sameNotification ->
                    if (sinceLast <= LONG_WINDOW_MS) strong(Reason.REPOST) else null
                // Không có gì để phân biệt: chỉ coi là đăng lại trong khoảng ngắn, và nhường cho
                // bằng chứng rõ hơn (vd thư của một giao dịch mới cùng số tiền + nội dung).
                now - posted.t in 0..REPOST_WINDOW_MS -> Evidence(Reason.REPOST, WEAK_REPOST_RANK)
                else -> null
            }
        }
        if (!crossCheck) return null
        if (sinceFirst > LONG_WINDOW_MS) return null
        if (r.amount != s.amount) return null
        if (r.directionKnown && s.directionKnown && r.income != s.income) return null
        if (r.balance != null && s.balance != null && r.balance != s.balance) return null

        val balanceEqual = r.balance != null && s.balance != null
        val content = contentRelation(s, r)
        val clocks = clockRelation(s.clocks, r.clocks)

        if (s.source in r.sources) {
            // Kênh này đã báo giao dịch r rồi -> thông báo mới thường là giao dịch khác,
            // trừ khi chắc chắn là cùng một giao dịch được trình bày lại.
            if (clocks == Rel.MISMATCH) return null
            if (balanceEqual) return strong(Reason.BALANCE)
            if (content == Rel.MATCH && (clocks == Rel.MATCH || sinceFirst <= SAME_SOURCE_WINDOW_MS)) {
                return strong(Reason.CONTENT)
            }
            return null
        }

        if (r.bankApp != null && s.bankApp != null && r.bankApp != s.bankApp) {
            // Hai app ngân hàng / ví khác nhau: chỉ trùng khi sát nhau (thanh toán ví trừ thẳng tài khoản).
            return if (content != Rel.MISMATCH && sinceFirst <= TIME_WINDOW_MS) strong(Reason.TIME) else null
        }

        if (balanceEqual) return strong(Reason.BALANCE)
        val bank = bankRelation(s.bank, r.bank)
        // Ngân hàng suy ra khác nhau (có thể đoán sai từ nội dung) -> chỉ tin trong khoảng ngắn.
        val strongWindow = if (bank == Rel.MISMATCH) SAME_BANK_WINDOW_MS else LONG_WINDOW_MS
        if (content == Rel.MATCH && sinceFirst <= strongWindow) return strong(Reason.CONTENT)
        if (clocks == Rel.MATCH && sinceFirst <= strongWindow) return strong(Reason.CLOCK)
        if (clocks == Rel.MISMATCH && sinceFirst <= strongWindow && clocksNear(s.clocks, r.clocks)) {
            return Evidence(Reason.CLOCK, NEAR_CLOCK_RANK)
        }
        val window = when {
            content == Rel.MISMATCH -> if (bank == Rel.MATCH) TIME_WINDOW_MS else 0L
            bank == Rel.MATCH -> SAME_BANK_WINDOW_MS
            else -> TIME_WINDOW_MS
        }
        return if (sinceFirst <= window) strong(Reason.TIME) else null
    }

    /** Giao dịch đã ghi nhận mà thông báo [s] báo lại (bằng chứng mạnh nhất, mới nhất trước). */
    fun findDuplicate(seen: List<Seen>, s: Signature, now: Long, crossCheck: Boolean = true): Match? {
        var best: Seen? = null
        var bestEvidence: Evidence? = null
        for (r in seen) {
            val e = evidence(s, r, now, crossCheck) ?: continue
            val b = bestEvidence
            if (b == null || e.rank < b.rank || (e.rank == b.rank && r.t > best!!.t)) {
                best = r
                bestEvidence = e
            }
        }
        return if (best == null || bestEvidence == null) null else Match(best, bestEvidence.reason)
    }

    /**
     * Kiểm tra thông báo [s] với danh sách [seen] rồi trả danh sách mới:
     * trùng -> gộp kênh này vào giao dịch cũ; không trùng -> ghi nhận giao dịch mới với [id].
     * [crossCheck] = false: chỉ lọc đúng thông báo đăng lại (người dùng tắt lọc trùng).
     */
    fun check(seen: List<Seen>, s: Signature, id: String, now: Long, crossCheck: Boolean = true): Outcome {
        val kept = prune(seen, now)
        val match = findDuplicate(kept, s, now, crossCheck)
        if (match == null) {
            val entry = Seen(
                id = id, t = now, last = now, amount = s.amount, income = s.income,
                directionKnown = s.directionKnown, balance = s.balance, content = s.content,
                texts = listOf(s.text), posts = listOf(Post(s.textKey, now, s.postKey)), clocks = s.clocks,
                sources = listOf(s.source), bankApp = s.bankApp, bank = s.bank,
            )
            return Outcome(null, (kept + entry).takeLast(MAX_ENTRIES))
        }
        val r = match.seen
        val adoptDirection = !r.directionKnown && s.directionKnown
        val merged = r.copy(
            last = now,
            income = if (adoptDirection) s.income else r.income,
            directionKnown = r.directionKnown || s.directionKnown,
            balance = r.balance ?: s.balance,
            content = r.content.ifEmpty { s.content },
            texts = (r.texts + s.text).distinct().take(MAX_TEXTS),
            posts = (if (r.posts.any { it.key == s.textKey }) r.posts else r.posts + Post(s.textKey, now, s.postKey))
                .takeLast(MAX_KEYS),
            clocks = (r.clocks + s.clocks).distinct().take(MAX_CLOCKS),
            sources = (r.sources + s.source).distinct(),
            bankApp = r.bankApp ?: s.bankApp,
            bank = r.bank ?: s.bank,
        )
        return Outcome(Match(merged, match.reason), kept.map { if (it.id == r.id) merged else it })
    }

    /** Bỏ mục quá hạn hoặc có mốc thời gian ở tương lai (đồng hồ bị chỉnh lùi). */
    fun prune(seen: List<Seen>, now: Long): List<Seen> =
        seen.filter { now - it.last in 0..LONG_WINDOW_MS && it.t <= now }

    // ------------------------------------------------------------- Lưu trữ

    fun encode(seen: List<Seen>): String {
        val arr = JSONArray()
        for (e in seen) {
            arr.put(
                JSONObject()
                    .put("id", e.id)
                    .put("t", e.t)
                    .put("last", e.last)
                    .put("amount", e.amount)
                    .put("income", e.income)
                    .put("dir", e.directionKnown)
                    .put("balance", e.balance ?: JSONObject.NULL)
                    .put("content", e.content)
                    .put("texts", JSONArray(e.texts))
                    .put(
                        "posts",
                        JSONArray().also { a ->
                            e.posts.forEach {
                                a.put(JSONObject().put("k", it.key).put("t", it.t).put("n", it.notif ?: JSONObject.NULL))
                            }
                        },
                    )
                    .put("clocks", JSONArray(e.clocks))
                    .put("sources", JSONArray(e.sources))
                    .put("bankApp", e.bankApp ?: JSONObject.NULL)
                    .put("bank", e.bank ?: JSONObject.NULL)
            )
        }
        return arr.toString()
    }

    fun decode(raw: String?): List<Seen> {
        if (raw.isNullOrEmpty()) return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).mapNotNull { i ->
                val o = arr.optJSONObject(i) ?: return@mapNotNull null
                val id = o.optString("id")
                if (id.isEmpty() || !o.has("amount")) return@mapNotNull null
                Seen(
                    id = id,
                    t = o.optLong("t"),
                    last = o.optLong("last", o.optLong("t")),
                    amount = o.optLong("amount"),
                    income = o.optBoolean("income"),
                    directionKnown = o.optBoolean("dir", true),
                    balance = if (o.isNull("balance")) null else o.optLong("balance"),
                    content = o.optString("content"),
                    texts = o.optJSONArray("texts").strings(),
                    posts = o.optJSONArray("posts").let { a ->
                        if (a == null) emptyList() else (0 until a.length()).mapNotNull { j ->
                            val p = a.optJSONObject(j) ?: return@mapNotNull null
                            p.optString("k").ifEmpty { null }?.let {
                                Post(it, p.optLong("t"), if (p.isNull("n")) null else p.optString("n").ifEmpty { null })
                            }
                        }
                    },
                    clocks = o.optJSONArray("clocks").strings().filter { validClock.matches(it) },
                    sources = o.optJSONArray("sources").strings(),
                    bankApp = if (o.isNull("bankApp")) null else o.optString("bankApp").ifEmpty { null },
                    bank = if (o.isNull("bank")) null else o.optString("bank").ifEmpty { null },
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun JSONArray?.strings(): List<String> {
        if (this == null) return emptyList()
        return (0 until length()).mapNotNull { optString(it).ifEmpty { null } }
    }
}
