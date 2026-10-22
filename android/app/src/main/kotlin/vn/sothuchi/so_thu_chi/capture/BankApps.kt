package vn.sothuchi.so_thu_chi.capture

/** Danh sách ngân hàng / ví (giữ đồng bộ với lib/capture/bank_apps.dart). */
object BankApps {
    data class Bank(val key: String, val name: String, val packages: List<String>, val aliases: List<String>)

    val all: List<Bank> = listOf(
        Bank("mbbank", "MB Bank", listOf("com.mbmobile"), listOf("mbbank", "mb bank", "mb ")),
        Bank("vcb", "Vietcombank", listOf("com.VCB"), listOf("vietcombank", "vcb")),
        Bank("tcb", "Techcombank", listOf("vn.com.techcombank.bb.app"), listOf("techcombank", "tcb")),
        Bank("bidv", "BIDV", listOf("com.vnpay.bidv"), listOf("bidv")),
        Bank("vietinbank", "VietinBank", listOf("com.vietinbank.ipay"), listOf("vietinbank", "vtb")),
        Bank("agribank", "Agribank", listOf("com.vnpay.Agribank3g"), listOf("agribank")),
        Bank("acb", "ACB", listOf("mobile.acb.com.vn"), listOf("acb")),
        Bank("tpbank", "TPBank", listOf("com.tpb.mb.gprsandroid"), listOf("tpbank")),
        Bank("vpbank", "VPBank", listOf("com.vnpay.vpbankonline"), listOf("vpbank")),
        Bank("sacombank", "Sacombank", listOf("com.sacombank.ewallet"), listOf("sacombank", "stb")),
        Bank("vib", "VIB", listOf("com.vib.myvib2"), listOf("vib")),
        Bank("hdbank", "HDBank", listOf("com.vnpay.hdbank"), listOf("hdbank")),
        Bank("msb", "MSB", listOf("vn.com.msb.smartBanking"), listOf("msb")),
        Bank("shb", "SHB", listOf("vn.shb.mbanking"), listOf("shb")),
        Bank("seabank", "SeABank", listOf("vn.com.seabank.mb1"), listOf("seabank")),
        Bank("ocb", "OCB", listOf("vn.com.ocb.awe"), listOf("ocb")),
        Bank("lpbank", "LPBank", listOf("vn.com.lpb.lienviet24h"), listOf("lpbank", "lienvietpostbank")),
        Bank("timo", "Timo", listOf("io.lifestyle.plus"), listOf("timo")),
        Bank("cake", "Cake", listOf("xyz.be.cake"), listOf("cake")),
        Bank("momo", "MoMo", listOf("com.mservice.momotransfer"), listOf("momo")),
        Bank("zalopay", "ZaloPay", listOf("vn.com.vng.zalopay"), listOf("zalopay")),
        Bank("viettelmoney", "Viettel Money", listOf("com.bplus.vtpay"), listOf("viettel money", "viettelpay")),
    )

    val smsPackages: List<String> = listOf(
        "com.google.android.apps.messaging",
        "com.samsung.android.messaging",
        "com.android.mms",
        "com.android.messaging",
        "com.oneplus.mms",
        "com.coloros.mms",
        "com.vivo.message",
    )

    fun byPackage(pkg: String?): Bank? = if (pkg == null) null else all.firstOrNull { pkg in it.packages }

    fun byKey(key: String?): Bank? = if (key == null) null else all.firstOrNull { it.key == key }
}
