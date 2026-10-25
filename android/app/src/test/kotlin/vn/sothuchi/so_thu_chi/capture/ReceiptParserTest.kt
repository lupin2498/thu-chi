package vn.sothuchi.so_thu_chi.capture

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.sothuchi.so_thu_chi.capture.ReceiptParser.Line

/** Biên lai "Chuyển khoản thành công" chia sẻ từ app ngân hàng (chữ OCR kèm kích thước). */
class ReceiptParserTest {

    // Bố cục giống màn hình kết quả chuyển khoản: số tiền in to, các dòng nhãn - giá trị.
    private val mbReceipt = listOf(
        Line("MB", 30, 40, 40),
        Line("Chuyển khoản thành công!", 34, 140, 200),
        Line("150,000 VND", 72, 200, 300),
        Line("Một trăm năm mươi nghìn đồng", 24, 290, 220),
        Line("16:30 - 22/10/2026", 22, 330, 380),
        Line("Tên người thụ hưởng", 24, 420, 40),
        Line("NGUYEN VAN A", 24, 422, 600),
        Line("Tài khoản thụ hưởng", 24, 470, 40),
        Line("0123456789", 24, 471, 680),
        Line("Ngân hàng thụ hưởng", 24, 520, 40),
        Line("Vietcombank", 24, 520, 640),
        Line("Nội dung", 24, 570, 40),
        Line("NGUYEN VAN B chuyen tien an trua", 24, 572, 380),
        Line("Phí giao dịch", 24, 620, 40),
        Line("1,100 VND", 26, 621, 700),
        Line("Mã giao dịch", 24, 670, 40),
        Line("FT26295123456789", 24, 672, 520),
    )

    @Test
    fun picksBiggestAmountAndContent() {
        val r = ReceiptParser.parse(mbReceipt, "com.mbmobile")
        assertNotNull(r)
        assertEquals(150000L, r!!.amount)
        assertFalse(r.isIncome)
        assertEquals("NGUYEN VAN B chuyen tien an trua", r.content)
        assertEquals("mbbank", r.bankKey)
    }

    @Test
    fun orderIndependentOfOcrBlockOrder() {
        // ML Kit có thể trả cột giá trị trước cột nhãn.
        val r = ReceiptParser.parse(mbReceipt.reversed(), null)
        assertEquals(150000L, r!!.amount)
        assertEquals("NGUYEN VAN B chuyen tien an trua", r.content)
    }

    @Test
    fun recipientWhenNoContent() {
        val lines = mbReceipt.filterNot { it.text.startsWith("Nội dung") || it.text.startsWith("NGUYEN VAN B") }
        val r = ReceiptParser.parse(lines, null)
        assertEquals("Chuyển tới NGUYEN VAN A", r!!.content)
    }

    @Test
    fun feeNeverChosen() {
        // Phí in to hơn cũng không được chọn.
        val lines = listOf(
            Line("Giao dịch thành công", 30, 100),
            Line("Phí: 5,500 VND", 80, 200),
            Line("Số tiền", 24, 300),
            Line("2.500.000 đ", 40, 330),
        )
        assertEquals(2500000L, ReceiptParser.parse(lines)!!.amount)
    }

    @Test
    fun sameRowLabelAndValue() {
        val lines = listOf(
            Line("Chuyển tiền thành công", 30, 100),
            Line("500.000đ", 60, 160),
            Line("Lời nhắn: tra tien nha", 24, 300),
        )
        val r = ReceiptParser.parse(lines)!!
        assertEquals(500000L, r.amount)
        assertEquals("tra tien nha", r.content)
    }

    @Test
    fun incomingTransfer() {
        val lines = listOf(
            Line("Nhận tiền thành công", 30, 100),
            Line("+1,000,000 VND", 60, 160),
            Line("Người chuyển: NGUYEN VAN C", 24, 300),
        )
        val r = ReceiptParser.parse(lines)!!
        assertEquals(1000000L, r.amount)
        assertTrue(r.isIncome)
    }

    @Test
    fun sharedTextUsesNotificationParser() {
        val text = "TK 0xxx6789|GD: -50,000VND 22/10/26 07:45 |SD: 1,950,000VND|ND: mua xang"
        val r = ReceiptParser.parse(ReceiptParser.linesFromText(text), "com.mbmobile")!!
        assertEquals(50000L, r.amount)
        assertEquals("mua xang", r.content)
        val t2 = "Chuyển tiền thành công!\nSố tiền: 320.000 VND\nNội dung: hoc phi"
        val r2 = ReceiptParser.parse(ReceiptParser.linesFromText(t2))!!
        assertEquals(320000L, r2.amount)
        assertEquals("hoc phi", r2.content)
    }

    @Test
    fun nothingUseful() {
        assertNull(ReceiptParser.parse(emptyList()))
        assertNull(ReceiptParser.parse(listOf(Line("Ảnh chụp màn hình", 30, 0))))
        assertNull(ReceiptParser.parse(listOf(Line("Mã OTP 123456 cho giao dịch 1,000,000 VND", 30, 0))))
    }

    @Test
    fun shareCaptureJson() {
        val c = ShareCapture.build(mbReceipt, "com.mbmobile", now = 123L)
        assertEquals(150000L, c.getLong("amount"))
        assertEquals("mbbank", c.getString("bankKey"))
        assertEquals(123L, c.getLong("time"))
        val empty = ShareCapture.build(emptyList(), null)
        assertEquals(0L, empty.getLong("amount"))
        assertTrue(empty.isNull("content"))
    }
}
