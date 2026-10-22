package vn.sothuchi.so_thu_chi

import android.content.ComponentName
import android.os.Bundle
import android.service.notification.NotificationListenerService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import vn.sothuchi.so_thu_chi.capture.BankNotificationListener
import vn.sothuchi.so_thu_chi.capture.CaptureChannelHandler

class MainActivity : FlutterActivity() {
    private var channel: CaptureChannelHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = CaptureChannelHandler(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Sau khi cập nhật app, một số máy không tự gắn lại dịch vụ đọc thông báo.
        if (CaptureChannelHandler.isListenerEnabled(this)) {
            try {
                NotificationListenerService.requestRebind(ComponentName(this, BankNotificationListener::class.java))
            } catch (e: Exception) {
                // bỏ qua
            }
        }
    }

    override fun onDestroy() {
        channel?.dispose()
        channel = null
        super.onDestroy()
    }
}
