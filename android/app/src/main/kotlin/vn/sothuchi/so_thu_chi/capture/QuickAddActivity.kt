package vn.sothuchi.so_thu_chi.capture

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import org.json.JSONObject

/**
 * Cửa sổ ghi nhanh trong suốt hiện trên ứng dụng ngân hàng.
 * Chạy Flutter với điểm vào riêng `quickAddMain` (lib/main.dart).
 *
 * Mở bằng: thông báo biến động số dư (bản full) hoặc nút "Chia sẻ" biên lai của app ngân hàng
 * (ảnh -> OCR, chữ -> phân tích) ở cả hai bản.
 */
class QuickAddActivity : FlutterActivity() {

    private var channel: CaptureChannelHandler? = null

    /** Đang đọc nội dung chia sẻ (OCR chạy nền). */
    private var processingShare = false

    /** Dart đã hỏi giao dịch ban đầu; giao dịch đến sau sẽ được đẩy qua onNewCapture. */
    private var launchDelivered = false
    private val launchWaiters = mutableListOf<(Map<String, Any?>?) -> Unit>()

    override fun getDartEntrypointFunctionName(): String = "quickAddMain"

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = CaptureChannelHandler(this, flutterEngine.dartExecutor.binaryMessenger, this)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) handleShare(intent)
        CapturePresenter.onPopupShown(this, currentCaptureId())
    }

    override fun onResume() {
        super.onResume()
        CapturePresenter.onPopupShown(this, currentCaptureId())
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (handleShare(intent)) return
        val id = intent.getStringExtra(CapturePresenter.EXTRA_CAPTURE_ID)
        CapturePresenter.onPopupShown(this, id)
        val capture = CaptureStore.get(this, id) ?: return
        channel?.sendNewCapture(CaptureStore.toMap(capture))
    }

    override fun onDestroy() {
        channel?.dispose()
        channel = null
        super.onDestroy()
    }

    fun currentCaptureId(): String? = intent?.getStringExtra(CapturePresenter.EXTRA_CAPTURE_ID)

    /** Giao dịch mở cửa sổ (chờ OCR xong nếu đang đọc ảnh chia sẻ). */
    fun launchCapture(callback: (Map<String, Any?>?) -> Unit) {
        if (processingShare) {
            launchWaiters.add(callback)
            return
        }
        launchDelivered = true
        callback(CaptureStore.get(this, currentCaptureId())?.let { CaptureStore.toMap(it) })
    }

    private fun handleShare(intent: Intent?): Boolean {
        if (intent?.action != Intent.ACTION_SEND) return false
        // Ứng dụng đã chia sẻ (thường là app ngân hàng) -> nhận diện ngân hàng.
        val source = referrer?.takeIf { it.scheme == "android-app" }?.host
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        val uri: Uri? = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
        // Xử lý xong thì bỏ action để không xử lý lại khi Activity được tạo lại.
        intent.action = null
        processingShare = true
        if (uri != null) {
            ReceiptOcr.recognize(this, uri) { lines ->
                val all = (lines ?: emptyList()) + (text?.let { ReceiptParser.linesFromText(it) } ?: emptyList())
                finishShare(ShareCapture.build(all, source))
            }
        } else {
            finishShare(ShareCapture.build(ReceiptParser.linesFromText(text.orEmpty()), source))
        }
        return true
    }

    private fun finishShare(capture: JSONObject) {
        CaptureStore.add(this, capture)
        val id = capture.getString("id")
        intent?.putExtra(CapturePresenter.EXTRA_CAPTURE_ID, id)
        CapturePresenter.onPopupShown(this, id)
        processingShare = false
        val map = CaptureStore.toMap(capture)
        if (launchWaiters.isNotEmpty()) {
            launchDelivered = true
            val waiters = launchWaiters.toList()
            launchWaiters.clear()
            waiters.forEach { it(map) }
        } else if (launchDelivered) {
            channel?.sendNewCapture(map)
        }
    }

    companion object {
        fun intent(ctx: Context, captureId: String?): Intent =
            Intent(ctx, QuickAddActivity::class.java).apply {
                addFlags(CapturePresenter.intentFlags())
                if (captureId != null) putExtra(CapturePresenter.EXTRA_CAPTURE_ID, captureId)
            }
    }
}
