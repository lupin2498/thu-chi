package vn.sothuchi.so_thu_chi.capture

/**
 * Đọc số tiền / nội dung từ biên lai chuyển khoản mà người dùng "Chia sẻ" từ app ngân hàng
 * (ảnh đã OCR -> các dòng chữ kèm kích thước, hoặc chữ chia sẻ trực tiếp).
 * Thuần Kotlin để unit test.
 */
object ReceiptParser {

    /** Một dòng chữ; [height] = chiều cao chữ (px) để nhận ra số tiền in to nhất trên biên lai. */
    data class Line(val text: String, val height: Int = 0, val top: Int = 0, val left: Int = 0)

    data class Result(
        val amount: Long,
        val isIncome: Boolean,
        val content: String?,
        val bankKey: String?,
    )

    private class Cand(val index: Int, val value: Long, val sign: Int, val currency: Boolean, val height: Int, val labeled: Boolean)

    private val money = Regex(
        "(?<![A-Za-z0-9_])([+\\-−]\\s?)?(\\d{1,3}(?:[.,]\\d{3})+)(?:[.,]\\d{1,2}(?!\\d))?(?![\\d/:])" +
            "(\\s?(?:VND|VNĐ|vnđ|vnd|Vnd|đồng|dong|đ|₫|d(?![a-zA-ZÀ-ỹ])))?"
    )
    private val combining = Regex("[\\u0300-\\u036f]")

    /** Dòng chứa các từ này không phải số tiền giao dịch (phí, số dư, số tài khoản...). */
    private val skipWords = listOf(
        "phi", "fee", "so du", "han muc", "kha dung", "balance", "tai khoan", "stk", "so tk",
        "ma gd", "ma giao dich", "tham chieu", "so ct", "hotline", "dien thoai", "sdt", "ma qr",
    )
    private val contentLabels = listOf(
        "noi dung chuyen khoan", "noi dung chuyen tien", "noi dung giao dich", "noi dung", "loi nhan",
        "dien giai", "mo ta", "message", "description", "remark",
    )
    private val recipientLabels = listOf(
        "ten nguoi thu huong", "nguoi thu huong", "ten nguoi nhan", "nguoi nhan", "ten tai khoan nhan",
        "chu tai khoan", "beneficiary",
    )
    private val incomeWords = listOf("nhan tien", "nhan duoc", "duoc cong", "da nhan", "tien vao", "nhan chuyen khoan")
    private val otpWords = listOf("otp", "ma xac thuc", "ma xac nhan")

    /** Xếp các dòng theo hàng (trên -> dưới), cùng hàng thì trái -> phải. */
    fun orderLines(lines: List<Line>): List<Line> {
        if (lines.none { it.height > 0 }) return lines
        val sorted = lines.sortedBy { it.top }
        val rows = mutableListOf<MutableList<Line>>()
        for (l in sorted) {
            val row = rows.lastOrNull()
            val ref = row?.first()
            val tol = maxOf(8, (minOf(ref?.height ?: l.height, l.height) * 0.6).toInt())
            if (ref != null && l.top - ref.top <= tol) row.add(l) else rows.add(mutableListOf(l))
        }
        return rows.flatMap { r -> r.sortedBy { it.left } }
    }

    fun parse(rawLines: List<Line>, packageName: String? = null): Result? {
        val lines = orderLines(
            rawLines.map { it.copy(text = it.text.replace(combining, "").replace(' ', ' ').trim()) }
                .filter { it.text.isNotEmpty() }
        )
        if (lines.isEmpty()) return null
        val full = lines.joinToString("\n") { it.text }
        val folded = BankParser.fold(full)
        if (otpWords.any { folded.contains(it) }) return null
        val foldedLines = lines.map { BankParser.fold(it.text) }
        val bankKey = BankApps.byPackage(packageName)?.key ?: BankParser.detectBankKey(folded)
        val hasHeights = lines.any { it.height > 0 }

        // Chữ chia sẻ (không có kích thước): thử bộ phân tích thông báo trước.
        if (!hasHeights) {
            BankParser.parse(full, null, packageName, strict = false)?.let { r ->
                return Result(r.amount, r.isIncome, r.content ?: findContent(lines, foldedLines), r.bankKey ?: bankKey)
            }
        }

        val cands = mutableListOf<Cand>()
        for ((i, l) in lines.withIndex()) {
            val lf = foldedLines[i]
            if (skipWords.any { lf.contains(it) } && !lf.contains("so tien")) continue
            val prev = if (i > 0) foldedLines[i - 1] else ""
            // Nhãn ở dòng trước (vd "Phí giao dịch" / "Số tiền") khi dòng đó không có số.
            val prevIsLabel = prev.isNotEmpty() && !prev.any { it.isDigit() }
            if (prevIsLabel && skipWords.any { prev.contains(it) }) continue
            val labeled = lf.contains("so tien") || (prevIsLabel && prev.contains("so tien"))
            for (m in money.findAll(l.text)) {
                val value = parseGrouped(m.groupValues[2]) ?: continue
                if (value < 1000) continue
                val signText = m.groups[1]?.value?.trim()
                cands.add(
                    Cand(
                        index = i,
                        value = value,
                        sign = when (signText) { null -> 0; "+" -> 1; else -> -1 },
                        currency = m.groups[3] != null,
                        height = l.height,
                        labeled = labeled,
                    )
                )
            }
        }

        val best = if (hasHeights) {
            // Số tiền giao dịch là dòng số tiền in to nhất trên biên lai.
            cands.maxWithOrNull(
                compareBy<Cand> { it.height }
                    .thenBy { if (it.labeled) 1 else 0 }
                    .thenBy { if (it.currency) 1 else 0 }
                    .thenByDescending { it.index }
            )
        } else {
            cands.firstOrNull { it.labeled } ?: cands.firstOrNull { it.currency } ?: cands.firstOrNull()
        }

        if (best == null) {
            val r = BankParser.parse(full, null, packageName, strict = false) ?: return null
            return Result(r.amount, r.isIncome, r.content ?: findContent(lines, foldedLines), r.bankKey ?: bankKey)
        }

        val isIncome = when {
            best.sign > 0 -> true
            best.sign < 0 -> false
            else -> incomeWords.any { folded.contains(it) } && !folded.contains("chuyen khoan thanh cong")
        }
        var content = findContent(lines, foldedLines)
        if (content == null && !isIncome) {
            findValue(lines, foldedLines, recipientLabels)?.let { content = "Chuyển tới $it" }
        }
        return Result(best.value, isIncome, content, bankKey)
    }

    private fun findContent(lines: List<Line>, folded: List<String>): String? =
        findValue(lines, folded, contentLabels)

    /** Giá trị của nhãn: phần sau nhãn trên cùng dòng, hoặc dòng kế tiếp. */
    private fun findValue(lines: List<Line>, folded: List<String>, labels: List<String>): String? {
        for ((i, f) in folded.withIndex()) {
            val label = labels.firstOrNull { f.startsWith(it) } ?: continue
            var rest = lines[i].text.substring(minOf(label.length, lines[i].text.length))
                .trimStart(' ', ':', '-', '：').trim()
            if (rest.isEmpty() && i + 1 < lines.size) {
                val next = folded[i + 1]
                // Dòng kế tiếp lại là một nhãn khác -> không có giá trị.
                if ((contentLabels + recipientLabels + skipWords).none { next.startsWith(it) }) {
                    rest = lines[i + 1].text.trim()
                }
            }
            if (rest.isNotEmpty()) return if (rest.length > 140) rest.substring(0, 140) + "…" else rest
        }
        return null
    }

    private fun parseGrouped(s: String): Long? {
        val digits = s.filter { it.isDigit() }
        if (digits.isEmpty() || digits.length > 15) return null
        return digits.toLongOrNull()
    }

    /** Tách chữ chia sẻ thành các dòng (không có kích thước). */
    fun linesFromText(text: String): List<Line> = text.split('\n').map { Line(it) }
}
