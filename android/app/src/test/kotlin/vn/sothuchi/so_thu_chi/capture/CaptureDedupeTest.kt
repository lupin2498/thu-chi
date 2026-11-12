package vn.sothuchi.so_thu_chi.capture

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.sothuchi.so_thu_chi.capture.CaptureDedupe.Reason

/** Lọc thông báo trùng theo số tiền + nội dung (và số dư / giờ GD khi có). */
class CaptureDedupeTest {
    private val t0 = 1_800_000_000_000L
    private val min = 60_000L
    private val hour = 60 * min

    private val mb = "com.mbmobile"
    private val vcb = "com.VCB"
    private val gmail = "com.google.android.gm"
    private val sms = "com.google.android.apps.messaging"
    private val mbTitle = "Thông báo biến động số dư"

    private fun mbText(
        amount: String = "-150,000",
        clock: String = "10:00",
        balance: String = "2,345,678",
        content: String = "NGUYEN VAN A chuyen tien an trua",
    ) = "TK 0xxx6789|GD: ${amount}VND 12/11/26 $clock |SD: ${balance}VND|ND: $content"

    private fun sig(pkg: String, title: String?, text: String, strict: Boolean = false): CaptureDedupe.Signature {
        val r = BankParser.parse(text, title, pkg, strict)
        assertNotNull("Không phân tích được: $text", r)
        return CaptureDedupe.signature(r!!, pkg, title, text)
    }

    /** Sổ dấu vết giả lập: đăng lần lượt các thông báo theo thời gian. */
    private inner class Book(private val crossCheck: Boolean = true) {
        var seen = emptyList<CaptureDedupe.Seen>()
        private var n = 0
        var lastMatch: CaptureDedupe.Match? = null

        /** Trả lý do bị lọc trùng, hoặc null nếu được ghi nhận là giao dịch mới. */
        fun post(pkg: String, title: String?, text: String, at: Long, strict: Boolean = false): Reason? {
            val out = CaptureDedupe.check(seen, sig(pkg, title, text, strict), "c${n++}", t0 + at, crossCheck)
            seen = out.seen
            lastMatch = out.match
            return out.match?.reason
        }

        fun app(text: String, at: Long) = post(mb, mbTitle, text, at)

        /** Thông báo của Gmail: tiêu đề = người gửi, nội dung = tiêu đề thư + trích đoạn. */
        fun mail(body: String, at: Long, sender: String = "MB Bank") =
            post(gmail, sender, "Thông báo biến động số dư\n$body", at, strict = true)
    }

    // ------------------------------------------------ Ngân hàng báo, Gmail báo lại

    @Test
    fun gmailRepeatsBankNotificationSameAmountAndContent() {
        val mail = "Kính gửi Quý khách, tài khoản 0xxx6789 vừa phát sinh giao dịch: -150,000 VND. " +
            "Nội dung: NGUYEN VAN A chuyen tien an trua"
        for (delay in listOf(20_000L, 5 * min, 3 * hour, 11 * hour)) {
            val b = Book()
            assertNull(b.app(mbText(), 0))
            assertEquals("sau ${delay / 1000}s", Reason.CONTENT, b.mail(mail, delay))
            assertEquals(1, b.seen.size)
            assertEquals(listOf(mb, "$gmail|mbbank"), b.seen[0].sources)
        }
        // Quá 12 giờ: coi là giao dịch khác.
        val b = Book()
        b.app(mbText(), 0)
        assertNull(b.mail(mail, 13 * hour))
    }

    @Test
    fun gmailFirstThenBankApp() {
        val b = Book()
        assertNull(b.mail("Giao dịch: -150,000 VND. Nội dung: NGUYEN VAN A chuyen tien an trua", 0))
        assertEquals(Reason.CONTENT, b.app(mbText(), 2 * min))
    }

    @Test
    fun gmailWithBalanceOnly() {
        val b = Book()
        b.app(mbText(), 0)
        assertEquals(Reason.BALANCE, b.mail("TK 0xxx6789 GD: -150,000VND. Số dư: 2,345,678 VND", 2 * hour))
    }

    @Test
    fun gmailWithTransactionTimeOnly() {
        val b = Book()
        b.app(mbText(), 0)
        assertEquals(Reason.CLOCK, b.mail("TK 0xxx6789 phát sinh giao dịch -150,000 VND lúc 10:00 12/11/2026", 2 * hour))
        // Cùng số tiền nhưng giờ GD khác, không có gì khác để so -> sau 10 phút là giao dịch khác.
        assertNull(b.mail("TK 0xxx6789 phát sinh giao dịch -150,000 VND lúc 11:45 12/11/2026", 2 * hour + min))
    }

    @Test
    fun transactionTimeMayDifferByOneMinuteAcrossChannels() {
        val b = Book()
        b.app(mbText(clock = "23:59"), 0)
        // Thư ghi giờ lệch 1 phút (qua nửa đêm) vẫn là giao dịch đó; lệch 2 phút thì không đủ chắc.
        assertEquals(Reason.CLOCK, b.mail("TK 0xxx6789 phát sinh giao dịch -150,000 VND lúc 00:00:12", 3 * hour))
        val c = Book()
        c.app(mbText(clock = "10:00"), 0)
        assertNull(c.mail("TK 0xxx6789 phát sinh giao dịch -150,000 VND lúc 10:02", 3 * hour))
        // Cùng app thì giờ khác 1 phút là giao dịch khác (đã có test secondTransfer...).
        // Giờ trùng chính xác được ưu tiên hơn giờ lệch 1 phút.
        val d = Book()
        d.app("TK 0xxx6789|GD: -150,000VND 12/11/26 10:00|ND: tien dien", 0)
        d.app("TK 0xxx6789|GD: -150,000VND 12/11/26 10:01|ND: tien nuoc", min)
        assertEquals(Reason.CLOCK, d.mail("TK 0xxx6789 phát sinh giao dịch -150,000 VND lúc 10:00", 2 * min))
        assertEquals("c0", d.lastMatch!!.seen.id)
    }

    @Test
    fun gmailWithAmountOnlyUsesShortWindow() {
        val body = "TK 0xxx6789 vừa phát sinh giao dịch: -150,000 VND"
        val near = Book()
        near.app(mbText(), 0)
        assertEquals(Reason.TIME, near.mail(body, 8 * min))
        val far = Book()
        far.app(mbText(), 0)
        assertNull(far.mail(body, 11 * min))
    }

    @Test
    fun smsRepeatsWithReferencePrefixInContent() {
        val b = Book()
        b.app(mbText(content = "NGUYEN VAN A chuyen tien - Ma GD ACSP/ ab123456"), 0)
        // SMS không có số dư, nội dung thêm mã tham chiếu.
        val r = b.post(sms, "MBBank", "TK 0xxx6789 GD: -150,000VND ND: MBVCB.123456.NGUYEN VAN A chuyen tien", 40 * min, strict = true)
        assertEquals(Reason.CONTENT, r)
    }

    @Test
    fun truncatedMailSnippetStillMatchesContent() {
        // Trích đoạn thư trong thông báo Gmail bị cắt ngang nội dung.
        val cut = Book()
        cut.app(mbText(content = "NGUYEN VAN A chuyen tien an trua thang 11"), 0)
        assertEquals(Reason.CONTENT, cut.mail("Giao dịch: -150,000 VND. Nội dung: NGUYEN VAN A chuyen ti", 2 * hour))
        // Chiều ngược lại: thông báo app bị cắt, thư có đủ.
        val rev = Book()
        rev.app(mbText(content = "NGUYEN VAN A chuyen tien an tr"), 0)
        assertEquals(Reason.CONTENT, rev.mail("Giao dịch: -150,000 VND. Nội dung: NGUYEN VAN A chuyen tien an trua thang 11", 2 * hour))
        // Nội dung khác hẳn thì không khớp.
        val other = Book()
        other.app(mbText(content = "tien dien thang 11"), 0)
        assertNull(other.mail("Giao dịch: -150,000 VND. Nội dung: hoc phi ky 2", 2 * hour))
    }

    @Test
    fun unknownBankOtherSourceOnlyWithinTwoMinutes() {
        val near = Book()
        near.app(mbText(), 0)
        assertEquals(Reason.TIME, near.post("com.example.notes", "Ghi chú", "GD: -150,000VND", 90_000))
        val far = Book()
        far.app(mbText(), 0)
        assertNull(far.post("com.example.notes", "Ghi chú", "GD: -150,000VND", 3 * min))
    }

    // ------------------------------------------- Hai giao dịch thật giống nhau

    @Test
    fun secondTransferSameAmountSameContentOnSameAppIsKept() {
        val b = Book()
        assertNull(b.app(mbText(clock = "10:00", balance = "2,345,678"), 0))
        // Chuyển lần hai: cùng số tiền, cùng nội dung mặc định, số dư đã giảm.
        assertNull(b.app(mbText(clock = "10:02", balance = "2,195,678"), 2 * min))
        assertEquals(2, b.seen.size)
        // Không có số dư trong thông báo vẫn phân biệt được nhờ giờ GD.
        val c = Book()
        assertNull(c.app("TK 0xxx6789|GD: -150,000VND 12/11/26 10:00|ND: NGUYEN VAN A chuyen tien", 0))
        assertNull(c.app("TK 0xxx6789|GD: -150,000VND 12/11/26 10:01|ND: NGUYEN VAN A chuyen tien", min))
    }

    @Test
    fun eachTransactionIsFilteredOncePerChannel() {
        val b = Book()
        val mail1 = "Giao dịch: -150,000 VND. Số dư: 2,345,678 VND. Nội dung: NGUYEN VAN A chuyen tien an trua"
        val mail2 = "Giao dịch: -150,000 VND. Số dư: 2,195,678 VND. Nội dung: NGUYEN VAN A chuyen tien an trua"
        assertNull(b.app(mbText(clock = "10:00", balance = "2,345,678"), 0))
        assertEquals(Reason.BALANCE, b.mail(mail1, min))
        assertNull(b.app(mbText(clock = "10:05", balance = "2,195,678"), 5 * min))
        assertEquals(Reason.BALANCE, b.mail(mail2, 6 * min))
        assertEquals("c2", b.lastMatch!!.seen.id)
        assertEquals(2, b.seen.size)
    }

    @Test
    fun secondTransactionReportedByMailWithoutBalance() {
        // Thư không có số dư: thư của giao dịch 2 không được gộp nhầm vào giao dịch 1 rồi làm mất giao dịch 3.
        val b = Book()
        val mail = "Giao dịch: -150,000 VND. Nội dung: NGUYEN VAN A chuyen tien an trua"
        assertNull(b.app(mbText(clock = "10:00", balance = "2,345,678"), 0))
        assertEquals(Reason.CONTENT, b.mail(mail, min))
        assertNull(b.app(mbText(clock = "10:05", balance = "2,195,678"), 5 * min))
        assertEquals(Reason.CONTENT, b.mail(mail, 6 * min))
        assertEquals("c2", b.lastMatch!!.seen.id)
        assertNull(b.app(mbText(clock = "10:09", balance = "2,045,678"), 9 * min))
        assertEquals(3, b.seen.size)
    }

    @Test
    fun differentBalanceAcrossChannelsIsAnotherTransaction() {
        val b = Book()
        b.app(mbText(balance = "2,345,678"), 0)
        // Kênh khác báo cùng số tiền, cùng nội dung nhưng số dư khác -> giao dịch khác.
        val r = b.post(sms, "MBBank", mbText(clock = "10:01", balance = "2,195,678"), min, strict = true)
        assertNull(r)
    }

    @Test
    fun refundThenRetryIsNotFiltered() {
        val b = Book()
        assertNull(b.app(mbText(amount = "-50,000", clock = "10:00", balance = "1,000,000", content = "nap dien thoai"), 0))
        assertNull(b.app(mbText(amount = "+50,000", clock = "10:05", balance = "1,050,000", content = "hoan tien nap dien thoai"), 5 * min))
        // Trả lại lần nữa: cùng số tiền, cùng nội dung, số dư quay về như cũ.
        assertNull(b.app(mbText(amount = "-50,000", clock = "10:07", balance = "1,000,000", content = "nap dien thoai"), 7 * min))
        assertEquals(3, b.seen.size)
    }

    @Test
    fun internalTransferLegsAreBothKept() {
        val b = Book()
        assertNull(b.app(mbText(amount = "-1,000,000", content = "NGUYEN VAN A chuyen tien"), 0))
        val vcbText = "Số dư TK VCB 0011001234567 +1,000,000 VND lúc 12-11-2026 10:00:20. Số dư 7,345,678 VND. " +
            "Ref MBVCB.1234567.NGUYEN VAN A chuyen tien"
        assertNull(b.post(vcb, "Thông báo VCB", vcbText, 30_000))
        // Chân nhận báo qua SMS cũng không bị lọc.
        val c = Book()
        c.app(mbText(amount = "-1,000,000", content = "NGUYEN VAN A chuyen tien"), 0)
        assertNull(c.post(sms, "Vietcombank", vcbText, 30_000, strict = true))
    }

    // --------------------------------------------------- Ví + ngân hàng, 2 ngân hàng

    @Test
    fun walletPaymentChargedToBankWithinTwoMinutes() {
        val zalo = "Bạn đã thanh toán 89.000 VND cho Grab. Mã giao dịch 221026000123"
        val bank = mbText(amount = "-89,000", content = "ZALOPAY 221026000123")
        val near = Book()
        assertNull(near.post("vn.com.vng.zalopay", "Thanh toán thành công", zalo, 0))
        assertEquals(Reason.TIME, near.app(bank, 40_000))
        val far = Book()
        far.post("vn.com.vng.zalopay", "Thanh toán thành công", zalo, 0)
        assertNull(far.app(bank, 3 * min))
    }

    @Test
    fun twoBanksSameAmountSameContentAreDifferentTransactions() {
        // Trả tiền nhà từ hai ngân hàng: cùng số tiền, cùng nội dung, cách nhau 5 phút.
        val b = Book()
        assertNull(b.app(mbText(amount = "-3,000,000", content = "tien nha thang 11"), 0))
        val vcbText = "Số dư TK VCB 0011001234567 -3,000,000 VND lúc 12-11-2026 10:05:00. Số dư 1,000,000 VND. " +
            "Ref tien nha thang 11"
        assertNull(b.post(vcb, "Thông báo VCB", vcbText, 5 * min))
        // Sát nhau nhưng nội dung khác hẳn cũng không trùng.
        val c = Book()
        c.app("TK 0xxx6789|GD: -3,000,000VND|ND: tien nha thang 11", 0)
        assertNull(c.post(vcb, "Thông báo VCB", "TK VCB 0011 -3,000,000 VND. Ref hoc phi ky 2", 30_000))
    }

    @Test
    fun guessedBankMismatchOnlyTrustedBriefly() {
        val mail = "Giao dịch: -150,000 VND. Nội dung: NGUYEN VAN A chuyen tien an trua"
        val near = Book()
        near.app(mbText(), 0)
        assertEquals(Reason.CONTENT, near.mail(mail, 5 * min, sender = "Vietcombank"))
        val far = Book()
        far.app(mbText(), 0)
        assertNull(far.mail(mail, 30 * min, sender = "Vietcombank"))
    }

    // ------------------------------------------------------------ Cùng một kênh

    @Test
    fun repostedNotificationWindows() {
        // Có giờ GD / số dư: thông báo y hệt chắc chắn là một giao dịch.
        val strong = Book()
        assertNull(strong.app(mbText(), 0))
        assertEquals(Reason.REPOST, strong.app(mbText(), 5 * min))
        assertEquals(Reason.REPOST, strong.app(mbText(), 11 * hour))
        assertNull(strong.app(mbText(), 24 * hour))
        // Không có gì để phân biệt (ví điện tử): chỉ coi là đăng lại trong 10 phút.
        val momo = "Bạn đã chuyển thành công 150.000đ đến NGUYEN VAN A."
        val weak = Book()
        assertNull(weak.post("com.mservice.momotransfer", "Chuyển tiền thành công", momo, 0))
        assertEquals(Reason.REPOST, weak.post("com.mservice.momotransfer", "Chuyển tiền thành công", momo, 5 * min))
        // Khoảng 10 phút tính từ lần đầu thấy thông báo, không kéo dài theo mỗi lần đăng lại.
        assertEquals(Reason.REPOST, weak.post("com.mservice.momotransfer", "Chuyển tiền thành công", momo, 9 * min))
        assertNull(weak.post("com.mservice.momotransfer", "Chuyển tiền thành công", momo, 11 * min))
        assertEquals(2, weak.seen.size)
    }

    @Test
    fun sameChannelShowsTransactionAgainInAnotherLayout() {
        val b = Book()
        b.app(mbText(), 0)
        val first = "Giao dịch: -150,000 VND lúc 10:00. Số dư: 2,345,678 VND. Nội dung: NGUYEN VAN A chuyen tien an trua"
        assertEquals(Reason.BALANCE, b.mail(first, min))
        // Gmail gộp thư: cùng giao dịch, trình bày khác.
        val again = "MB Bank: TK 0xxx6789 GD -150,000 VND 10:00, số dư 2,345,678 VND"
        assertEquals(Reason.BALANCE, b.mail(again, 40 * min))
        // Thư khác của cùng người gửi cho giao dịch mới cùng số tiền (giờ khác) -> không lọc.
        assertNull(b.mail("Giao dịch: -150,000 VND lúc 14:20. Nội dung: NGUYEN VAN A chuyen tien an trua", 4 * hour))
    }

    @Test
    fun sameChannelTwoFormatsWithinOneMinute() {
        val pkg = "vn.com.techcombank.bb.app"
        val a = "Chuyển tiền thành công\nSố tiền: -500,000 VND\nNội dung: tra tien com thang 11"
        val c = "Biến động số dư\nSố tiền: -500,000 VND\nSố dư: 4,500,000 VND\nNội dung: tra tien com thang 11"
        val near = Book()
        assertNull(near.post(pkg, "Techcombank", a, 0))
        assertEquals(Reason.CONTENT, near.post(pkg, "Techcombank", c, 20_000))
        val far = Book()
        far.post(pkg, "Techcombank", a, 0)
        assertNull(far.post(pkg, "Techcombank", c, 5 * min))
    }

    // ----------------------------------------------------------------- Khác

    @Test
    fun unknownDirectionDoesNotBlockMatch() {
        val b = Book()
        assertNull(b.app(mbText(amount = "+150,000", content = "TRAN THI B tra tien hang"), 0))
        // Thư không ghi dấu +/- hay chữ thu/chi.
        val r = b.mail("Số tiền giao dịch: 150,000 VND. Nội dung: TRAN THI B tra tien hang", 3 * min)
        assertEquals(Reason.CONTENT, r)
        assertTrue(b.seen[0].income)
        // Chiều ngược nhau rõ ràng -> không trùng.
        assertNull(b.mail("Giao dịch: -150,000 VND. Nội dung: TRAN THI B tra tien hang", 4 * min, sender = "MBBank 2"))
    }

    @Test
    fun genericContentIsNotEvidence() {
        val b = Book()
        b.app(mbText(content = "chuyen tien"), 0)
        // "chuyển tiền" có trong mọi thư -> không dùng làm bằng chứng trùng.
        assertNull(b.mail("Quý khách đã chuyển tiền thành công. Giao dịch: -150,000 VND", 30 * min))
        assertEquals("", b.seen[0].content)
    }

    @Test
    fun differentAmountNeverMatches() {
        val b = Book()
        b.app(mbText(amount = "-150,000"), 0)
        assertNull(b.mail("Giao dịch: -151,000 VND. Nội dung: NGUYEN VAN A chuyen tien an trua", min))
    }

    @Test
    fun filterTurnedOffStillDropsExactReposts() {
        val b = Book(crossCheck = false)
        assertNull(b.app(mbText(), 0))
        assertEquals(Reason.REPOST, b.app(mbText(), min))
        assertNull(b.mail("Giao dịch: -150,000 VND. Nội dung: NGUYEN VAN A chuyen tien an trua", 2 * min))
        assertEquals(2, b.seen.size)
    }

    @Test
    fun strongestEvidenceWins() {
        val b = Book()
        b.app(mbText(clock = "10:00", balance = "2,345,678", content = "tien nuoc"), 0)
        b.app(mbText(clock = "10:00", balance = "2,195,678", content = "tien dien"), 20_000)
        // Thư của giao dịch đầu: khớp giờ với cả hai nhưng khớp số dư với giao dịch đầu.
        assertEquals(Reason.BALANCE, b.mail("GD: -150,000 VND lúc 10:00. Số dư: 2,345,678 VND", min))
        assertEquals("c0", b.lastMatch!!.seen.id)
    }

    @Test
    fun mergeFillsMissingDetails() {
        val b = Book()
        b.mail("TK 0xxx6789 vừa phát sinh giao dịch: -150,000 VND", 0)
        assertNull(b.seen[0].balance)
        assertEquals(Reason.TIME, b.app(mbText(), 30_000))
        val e = b.seen.single()
        assertEquals(2345678L, e.balance)
        assertTrue(e.content.contains("an trua"))
        assertEquals(listOf("10:00"), e.clocks)
        assertEquals("mbbank", e.bankApp)
        assertEquals(t0, e.t)
        assertEquals(t0 + 30_000, e.last)
        // Nhờ số dư vừa bổ sung, SMS đến sau 2 giờ vẫn nhận ra là trùng.
        val r = b.post(sms, "MBBank", "TK 0xxx6789|GD: -150,000VND|SD: 2,345,678VND", 2 * hour, strict = true)
        assertEquals(Reason.BALANCE, r)
    }

    @Test
    fun pruneAndCap() {
        val b = Book()
        b.app(mbText(amount = "-10,000", clock = "08:00"), 0)
        b.app(mbText(amount = "-20,000", clock = "20:30"), 12 * hour + min)
        assertEquals(1, b.seen.size)
        // Đồng hồ bị chỉnh lùi: bỏ mục ở tương lai.
        b.app(mbText(amount = "-30,000", clock = "07:00"), -hour)
        assertEquals(1, b.seen.size)
        val many = Book()
        for (i in 1..(CaptureDedupe.MAX_ENTRIES + 15)) {
            many.app(mbText(amount = "-${i},000", balance = "${9000 - i},000"), i * 1000L)
        }
        assertEquals(CaptureDedupe.MAX_ENTRIES, many.seen.size)
        assertEquals("c15", many.seen.first().id)
    }

    @Test
    fun encodeDecodeRoundTrip() {
        val b = Book()
        b.app(mbText(), 0)
        b.mail("Giao dịch: -150,000 VND. Nội dung: NGUYEN VAN A chuyen tien an trua", min)
        b.post("com.mservice.momotransfer", "Chuyển tiền thành công", "Bạn đã chuyển thành công 150.000đ đến NGUYEN VAN A.", 2 * min)
        assertEquals(b.seen, CaptureDedupe.decode(CaptureDedupe.encode(b.seen)))
        assertTrue(CaptureDedupe.decode(null).isEmpty())
        assertTrue(CaptureDedupe.decode("").isEmpty())
        assertTrue(CaptureDedupe.decode("không phải json").isEmpty())
        assertTrue(CaptureDedupe.decode("{\"a\":1}").isEmpty())
        // Mục hỏng bị bỏ, mục còn lại vẫn đọc được.
        assertEquals(1, CaptureDedupe.decode("[1, {\"x\":2}, {\"id\":\"k\",\"amount\":5,\"t\":7}]").size)
    }

    @Test
    fun normalizeHelpers() {
        assertEquals("so du 2 345 678vnd nguyen van a", CaptureDedupe.normalize("  Số dư: 2,345,678VND — NGUYỄN  Văn A!!"))
        // Dấu tổ hợp (NFD) như trong SMS.
        assertEquals("so du", CaptureDedupe.normalize("So\u0302\u0301 du\u031b"))
        assertEquals("", CaptureDedupe.normalize(" …— "))
        assertEquals(listOf("16:30", "07:05"), CaptureDedupe.clocksOf("22/10/26 16:30 và 7:05:59, mã 12:345, 25:10"))
        assertEquals(mb, CaptureDedupe.sourceKey(mb, "bất kỳ"))
        assertEquals("$gmail|mbbank", CaptureDedupe.sourceKey(gmail, "MB Bank (2)"))
        assertEquals("$gmail|mbbank", CaptureDedupe.sourceKey(gmail, "MB Bank"))
        assertEquals(sms, CaptureDedupe.sourceKey(sms, "0909 123 456"))
        assertEquals("", CaptureDedupe.sourceKey(null, null))
    }

    @Test
    fun signatureDetails() {
        val s = sig(mb, mbTitle, mbText(content = "NGUYEN VAN A chuyen tien - Ma GD ACSP/ ab123456"))
        assertEquals(150000L, s.amount)
        assertFalse(s.income)
        assertTrue(s.directionKnown)
        assertEquals(2345678L, s.balance)
        // Bộ phân tích đã cắt phần "- Ma GD ..." khỏi nội dung.
        assertEquals("nguyen van a chuyen tien", s.content)
        assertEquals(listOf("10:00"), s.clocks)
        assertTrue(s.strongText)
        assertEquals("mbbank", s.bankApp)
        // Cùng nội dung -> cùng khoá; khác gói -> khác khoá.
        assertEquals(s.textKey, sig(mb, mbTitle, mbText(content = "NGUYEN VAN A chuyen tien - Ma GD ACSP/ ab123456")).textKey)
        assertFalse(s.textKey == sig(sms, mbTitle, mbText(content = "NGUYEN VAN A chuyen tien - Ma GD ACSP/ ab123456")).textKey)
        // Nội dung dài bị cắt: bỏ từ cuối dở dang.
        val long = sig(mb, mbTitle, mbText(content = "thanh toan don hang " + "abcdefghi ".repeat(20)))
        assertFalse(long.content.endsWith("abcdefgh"))
        assertTrue(long.content.endsWith("abcdefghi"))
        val wallet = sig("com.mservice.momotransfer", "Chuyển tiền thành công", "Bạn đã chuyển thành công 150.000đ đến NGUYEN VAN A.")
        assertFalse(wallet.strongText)
        assertEquals("", wallet.content)
    }
}
