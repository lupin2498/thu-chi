package vn.sothuchi.so_thu_chi.capture

import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Chạy cùng bộ mẫu với test Dart để đảm bảo hai bản parser cho kết quả giống nhau. */
class BankParserTest {

    private fun fixtureFile(): File {
        val candidates = listOf(
            "../../test/fixtures/bank_notifications.json",
            "../test/fixtures/bank_notifications.json",
            "test/fixtures/bank_notifications.json",
        )
        return candidates.map { File(it) }.first { it.exists() }
    }

    @Test
    fun fixtures() {
        val arr = JSONArray(fixtureFile().readText())
        // Chống "pass giả" nếu org.json bản stub của android.jar được dùng thay bản thật.
        assertTrue("Đọc được quá ít mẫu: ${arr.length()}", arr.length() >= 25)
        val failures = mutableListOf<String>()
        for (i in 0 until arr.length()) {
            val f = arr.getJSONObject(i)
            val name = f.getString("name")
            val r = BankParser.parse(
                f.getString("text"),
                title = f.optString("title"),
                packageName = f.optString("package"),
                strict = f.optBoolean("strict", false),
            )
            if (f.isNull("expect")) {
                if (r != null) failures.add("$name: không được nhận là giao dịch, nhưng có $r")
                continue
            }
            val e = f.getJSONObject("expect")
            if (r == null) {
                failures.add("$name: không nhận được giao dịch")
                continue
            }
            if (r.amount != e.getLong("amount")) failures.add("$name: amount ${r.amount} != ${e.getLong("amount")}")
            val type = if (r.isIncome) "income" else "expense"
            if (type != e.getString("type")) failures.add("$name: type $type != ${e.getString("type")}")
            if (e.has("balance") && r.balance != e.getLong("balance")) {
                failures.add("$name: balance ${r.balance} != ${e.getLong("balance")}")
            }
            if (e.has("bank") && r.bankKey != e.getString("bank")) {
                failures.add("$name: bank ${r.bankKey} != ${e.getString("bank")}")
            }
            if (e.has("content") && r.content != e.getString("content")) {
                failures.add("$name: content '${r.content}' != '${e.getString("content")}'")
            }
            if (e.has("contentContains") && r.content?.contains(e.getString("contentContains")) != true) {
                failures.add("$name: content '${r.content}' thiếu '${e.getString("contentContains")}'")
            }
        }
        assertTrue(failures.joinToString("\n"), failures.isEmpty())
    }

    @Test
    fun edgeCases() {
        assertNull(BankParser.parse(""))
        assertNull(BankParser.parse("Chào mừng bạn đến MB Bank"))
        val r = BankParser.parse("💰 TK 0xxx1|GD: -10,000VND 22/10/26 10:00 |SD: 90,000VND|ND: test 🎉")
        assertNotNull(r)
        assertEquals(10000L, r!!.amount)
        val big = BankParser.parse("TK 0xxx1|GD: +1,234,567,890VND 22/10/26 10:00 |SD: 2,000,000,000VND")
        assertEquals(1234567890L, big!!.amount)
        assertTrue(big.isIncome)
        val long = BankParser.parse("TK 0xxx1|GD: -10,000VND|ND: " + "a".repeat(5000))
        assertEquals(10000L, long!!.amount)
        assertTrue(long.content!!.length <= 141)
    }
}
