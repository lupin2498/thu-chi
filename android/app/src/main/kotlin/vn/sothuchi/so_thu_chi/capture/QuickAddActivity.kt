package vn.sothuchi.so_thu_chi.capture

import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine

/**
 * Cửa sổ ghi nhanh trong suốt hiện trên ứng dụng ngân hàng.
 * Chạy Flutter với điểm vào riêng `quickAddMain` (lib/main.dart).
 */
class QuickAddActivity : FlutterActivity() {

    private var channel: CaptureChannelHandler? = null

    override fun getDartEntrypointFunctionName(): String = "quickAddMain"

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = CaptureChannelHandler(this, flutterEngine.dartExecutor.binaryMessenger, this)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        CapturePresenter.onPopupShown(this, currentCaptureId())
    }

    override fun onResume() {
        super.onResume()
        CapturePresenter.onPopupShown(this, currentCaptureId())
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
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

    companion object {
        fun intent(ctx: Context, captureId: String?): Intent =
            Intent(ctx, QuickAddActivity::class.java).apply {
                addFlags(CapturePresenter.intentFlags())
                if (captureId != null) putExtra(CapturePresenter.EXTRA_CAPTURE_ID, captureId)
            }
    }
}
