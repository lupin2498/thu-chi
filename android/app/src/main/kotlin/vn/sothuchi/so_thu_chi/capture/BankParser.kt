package vn.sothuchi.so_thu_chi.capture

/**
 * Bộ phân tích thông báo biến động số dư (bản Kotlin của lib/capture/bank_parser.dart).
 * Hai bản dùng chung bộ mẫu test/fixtures/bank_notifications.json; sửa một bên phải sửa cả bên kia.
 * Không phụ thuộc Android để chạy unit test thuần JVM.
 */
object BankParser {

    data class Result(
        val amount: Long,
        val isIncome: Boolean,
        val content: String?,
        val balance: Long?,
        val bankKey: String?,
        val score: Int,
    )

    private class Candidate(
        val start: Int,
        val end: Int,
        val value: Long,
        val sign: Int,
        val hasCurrency: Boolean,
        val hasGrouping: Boolean,
    ) {
        var score = 0
        var isBalance = false
    }

    private val money = Regex(
        "(?<![A-Za-z0-9_*])(?<![0-9][:/.,\\-])([+\\-−]\\s?)?((?:VND|VNĐ|vnd|vnđ|đ|₫)\\s?)?" +
            "(\\d{1,3}(?:[.,]\\d{3})+(?:[.,]\\d{1,2}(?!\\d))?|\\d+(?:[.,]\\d{1,2}(?!\\d))?)(?![\\d/:])" +
            "(\\s?(?:VND|VNĐ|vnđ|vnd|Vnd|đồng|dong|đ|₫|d(?![a-zA-ZÀ-ỹ])|k(?![a-zA-ZÀ-ỹ])))?"
    )
    private val txnLabel = Regex(
        "(?:^|[^a-z])(gd|ps|giao dich|so tien|so tien gd|phat sinh|thay doi|bien dong|amount|tien)\\s*[:=]?\\s*$"
    )
    private val verbLabel = Regex(
        "(chuyen|nhan|nhan duoc|thanh toan|tru|cong|giam|tang|rut|nap|chi|mua|hoan)\\s*(?:thanh cong|tien)?\\s*[:=]?\\s*$"
    )
    private val balanceLabel = Regex(
        "(?:^|[^a-z])(sd|sdc|sdkd|so du|so du kha dung|so du hien tai|so du cuoi|sd kha dung|balance|bal|du no|han muc|kha dung)\\s*(?:moi|tk|cuoi|hien tai|kha dung)?\\s*[:=]?\\s*$"
    )
    private val accountLabel = Regex(
        "(?:^|[^a-z])(tk|stk|so tk|tai khoan|account|acc|the|card|ma gd|so gd|ma giao dich|ref|ft|so ct|so the)\\s*[:=]?\\s*$"
    )
    private val contentLabel = Regex(
        "(?:^|[\\s|.;,(\\n])(nd|noi dung|noi dung gd|noi dung ck|mo ta|loi nhan|dien giai|ref|gd|chi tiet|description|remark|memo)(?:\\s*[:：]\\s*|\\s+)"
    )
    private val contentEnd = Regex(
        "(\\||\\n|\\s+(sd|so du|so du kha dung|so gd|ma gd|ma giao dich|sd kha dung)(?![a-z0-9])|\\.\\s*(sd|so du|ct tu|so gd|ma gd)(?![a-z0-9]))"
    )
    private val amountAfterLabel = Regex("^\\s*[+\\-−]?\\s?(VND|VNĐ|đ)?\\s?\\d")
    private val refPrefix = Regex("^(?:[A-Z]{2,10}\\.\\d{3,}\\.|FT\\d{6,}\\s|IBFT\\s|TKThe\\s:\\S+\\s*,?\\s*)")
    private val combining = Regex("[\\u0300-\\u036f]")
    private val oddSpaces = Regex("[\\u00a0\\u2007\\u2009\\u202f\\t\\r]")
    private val grouping = Regex("\\d[.,]\\d{3}")

    private val otpWords = listOf("otp", "ma xac thuc", "ma xac nhan", "mat khau", "smart otp", "khong cung cap")
    private val promoWords = listOf(
        "uu dai", "khuyen mai", "voucher", "giam gia", "qua tang", "tri an", "mien phi", "co hoi",
        "nhan ngay", "trung thuong", "hoan tien den", "giam den", "tang ngay",
    )
    private val txnKeywords = listOf(
        "bien dong", "giao dich", "thanh cong", "da chuyen", "nhan duoc", "vua nhan", "bi tru", "duoc cong",
        "tru tien", "cong tien", "chuyen tien", "thanh toan", "ghi no", "ghi co", "vua giam", "vua tang",
    )
    private val incomeWords = listOf(
        "nhan duoc", "vua nhan", "nhan tien", "da nhan", "nhan chuyen khoan", "duoc cong", "cong tien",
        "ghi co", "vua tang", "tang ", "hoan tien", "nap tien", "credit",
    )
    private val expenseWords = listOf(
        "da chuyen", "chuyen thanh cong", "chuyen tien thanh cong", "thanh toan", "bi tru", "tru tien",
        "ghi no", "vua giam", "giam ", "rut tien", "chi tieu", "debit",
    )

    fun parse(text: String, title: String? = null, packageName: String? = null, strict: Boolean = false): Result? {
        val raw = listOfNotNull(title?.trim()?.takeIf { it.isNotEmpty() }, text.trim()).joinToString("\n")
        if (raw.isBlank()) return null

        val original = raw.replace(combining, "").replace(oddSpaces, " ")
        val folded = fold(original)

        if (otpWords.any { folded.contains(it) }) return null

        val contentStart = findContentStart(original, folded)
        val candidates = ArrayList<Candidate>()
        for (m in money.findAll(original)) {
            val numText = m.groupValues[3]
            val value = parseNumber(numText) ?: continue
            if (value <= 0) continue
            val signText = m.groups[1]?.value?.trim()
            val sign = when (signText) {
                null -> 0
                "+" -> 1
                else -> -1
            }
            val cur1 = m.groups[2]?.value
            val cur2 = m.groups[4]?.value?.trim()
            val hasGrouping = grouping.containsMatchIn(numText)
            val digitsOnly = numText.filter { it.isDigit() }
            if (!hasGrouping && digitsOnly.length > 12) continue
            val hasK = cur2 != null && cur2.lowercase() == "k"
            val multiplier = if (hasK) 1000L else 1L
            candidates.add(
                Candidate(
                    start = m.range.first,
                    end = m.range.last + 1,
                    value = value * multiplier,
                    sign = sign,
                    hasCurrency = cur1 != null || (cur2 != null && !hasK),
                    hasGrouping = hasGrouping || hasK,
                )
            )
        }
        if (candidates.isEmpty()) return null

        for (c in candidates) {
            val prefix = segmentPrefix(folded, c.start)
            var s = 0
            if (c.sign != 0) s += 4
            if (c.hasCurrency) s += 3
            if (c.hasGrouping) s += 1
            if (txnLabel.containsMatchIn(prefix)) s += 5
            if (verbLabel.containsMatchIn(prefix)) s += 2
            if (balanceLabel.containsMatchIn(prefix)) {
                s -= 20
                c.isBalance = true
            }
            if (accountLabel.containsMatchIn(prefix)) s -= 20
            if (!c.hasGrouping && !c.hasCurrency && c.sign == 0) s -= 3
            if (contentStart != null && c.start > contentStart) s -= 6
            c.score = s
        }

        var best: Candidate? = null
        for (c in candidates) {
            if (best == null || c.score > best.score) best = c
        }
        if (best == null || best.score < 3) return null

        val bestPrefix = segmentPrefix(folded, best.start)
        val hasStrongLabel = txnLabel.containsMatchIn(bestPrefix)
        val labeled = hasStrongLabel || verbLabel.containsMatchIn(bestPrefix)
        val hasBalance = candidates.any { it.isBalance } || folded.contains("so du")
        val hasTxnKeyword = txnKeywords.any { folded.contains(it) }
        if (best.sign == 0 && !labeled) {
            if (!hasTxnKeyword || hasBalance) return null
        }

        val isPromo = promoWords.any { folded.contains(it) }
        if (isPromo && best.sign == 0 && !hasBalance) return null

        if (strict) {
            val clear = best.sign != 0 || hasStrongLabel
            val bankish = hasBalance || detectBankKey(folded) != null || BankApps.byPackage(packageName) != null
            if (!clear || !bankish) return null
            if (!best.hasCurrency && !best.hasGrouping) return null
        }

        val isIncome = direction(best, folded)
        var balance: Long? = candidates.firstOrNull { it.isBalance && it.start > best.start }?.value
        if (balance == null) balance = candidates.firstOrNull { it.isBalance }?.value

        return Result(
            amount = best.value,
            isIncome = isIncome,
            content = extractContent(original, folded),
            balance = balance,
            bankKey = BankApps.byPackage(packageName)?.key ?: detectBankKey(folded),
            score = best.score,
        )
    }

    private fun direction(best: Candidate, folded: String): Boolean {
        if (best.sign < 0) return false
        if (best.sign > 0) return true
        fun nearest(words: List<String>): Int {
            var bestDist = 1 shl 30
            for (w in words) {
                var idx = folded.indexOf(w)
                while (idx >= 0) {
                    val dist = if (idx <= best.start) best.start - idx else (idx - best.end) * 2 + 40
                    if (dist < bestDist) bestDist = dist
                    idx = folded.indexOf(w, idx + 1)
                }
            }
            return bestDist
        }
        return nearest(incomeWords) < nearest(expenseWords)
    }

    private fun segmentPrefix(folded: String, index: Int): String {
        val startIdx = maxOf(0, index - 32)
        var prefix = folded.substring(startIdx, index)
        val cut = prefix.indexOfLast { it == '|' || it == '\n' || it == ';' }
        if (cut >= 0) prefix = prefix.substring(cut + 1)
        var dot = -1
        for (i in prefix.length - 2 downTo 0) {
            if (prefix[i] == '.' && prefix[i + 1].isWhitespace()) {
                dot = i
                break
            }
        }
        if (dot >= 0) prefix = prefix.substring(dot + 1)
        return prefix.lowercase()
    }

    private fun findContentStart(original: String, folded: String): Int? {
        for (m in contentLabel.findAll(folded)) {
            val end = m.range.last + 1
            val after = original.substring(end)
            if (amountAfterLabel.containsMatchIn(after)) continue
            return end
        }
        return null
    }

    private fun extractContent(original: String, folded: String): String? {
        val start = findContentStart(original, folded) ?: return null
        val rest = folded.substring(start)
        val endMatch = contentEnd.find(rest)
        val end = if (endMatch == null) original.length else start + endMatch.range.first
        var content = original.substring(start, end).trim()
        content = content.replace(Regex("\\s+"), " ")
        content = refPrefix.replaceFirst(content, "")
        content = content.replace(Regex("^[\\s:.\\-]+|[\\s.;,\\-]+$"), "")
        if (content.isEmpty()) return null
        if (content.length > 140) content = content.substring(0, 140) + "…"
        return content
    }

    private fun detectBankKey(folded: String): String? {
        for (b in BankApps.all) {
            for (alias in b.aliases) {
                val a = alias.trim()
                if (Regex("(^|[^a-z])" + Regex.escape(a) + "($|[^a-z])").containsMatchIn(folded)) return b.key
            }
        }
        return null
    }

    private fun parseNumber(s: String): Long? {
        val t = s.trim()
        val intPart: String = when {
            Regex("^\\d+$").matches(t) -> t
            Regex("^\\d+[.,]\\d{1,2}$").matches(t) -> t.split('.', ',').first()
            else -> {
                val m = Regex("^(\\d{1,3}(?:[.,]\\d{3})+)(?:[.,]\\d{1,2})?$").find(t) ?: return null
                m.groupValues[1]
            }
        }
        val digits = intPart.filter { it != '.' && it != ',' }
        if (digits.isEmpty() || digits.length > 15) return null
        return digits.toLongOrNull()
    }

    private val foldMap: Map<Char, Char> = buildMap {
        val groups = mapOf(
            'a' to "àáạảãâầấậẩẫăằắặẳẵÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴ",
            'e' to "èéẹẻẽêềếệểễÈÉẸẺẼÊỀẾỆỂỄ",
            'i' to "ìíịỉĩÌÍỊỈĨ",
            'o' to "òóọỏõôồốộổỗơờớợởỡÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠ",
            'u' to "ùúụủũưừứựửữÙÚỤỦŨƯỪỨỰỬỮ",
            'y' to "ỳýỵỷỹỲÝỴỶỸ",
            'd' to "đĐ",
        )
        for ((base, chars) in groups) for (c in chars) put(c, base)
    }

    /** Bỏ dấu + chữ thường, giữ nguyên độ dài. */
    fun fold(input: String): String {
        val sb = StringBuilder(input.length)
        for (ch in input) {
            sb.append(foldMap[ch] ?: ch.lowercaseChar())
        }
        return sb.toString()
    }
}
