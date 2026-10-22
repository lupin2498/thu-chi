package vn.sothuchi.so_thu_chi.capture

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONObject
import vn.sothuchi.so_thu_chi.R
import java.text.NumberFormat
import java.util.Locale

/**
 * Hiển thị giao dịch vừa bắt được:
 *  1. Thẻ nổi nhỏ trên cùng màn hình (cần quyền "Hiển thị trên ứng dụng khác") – đồng thời
 *     cho phép mở Activity từ nền theo quy định Android 10+.
 *  2. Mở [QuickAddActivity] (cửa sổ ghi nhanh trong suốt có micro chờ sẵn).
 *  3. Nếu không mở được cửa sổ -> thông báo nhắc, chạm để ghi.
 */
object CapturePresenter {
    private const val TAG = "SoThuChiCapture"
    const val CHANNEL_ALERT = "capture_alert"
    const val CHANNEL_SILENT = "capture_silent"
    const val EXTRA_CAPTURE_ID = "capture_id"

    private val handler = Handler(Looper.getMainLooper())
    private var bannerView: View? = null
    private val removeBanner = Runnable { dismissBanner() }

    fun formatMoney(amount: Long): String =
        NumberFormat.getInstance(Locale.forLanguageTag("vi-VN")).format(amount) + " đ"

    fun present(ctx: Context, capture: JSONObject, showPopup: Boolean) {
        val app = ctx.applicationContext
        val id = capture.optString("id")
        val canOverlay = Settings.canDrawOverlays(app)
        if (!showPopup || !canOverlay) {
            notify(app, capture, headsUp = true)
            return
        }
        showBanner(app, capture)
        // Đợi thẻ nổi thực sự hiển thị rồi mới mở Activity (điều kiện mở từ nền trên Android 15+).
        handler.postDelayed({ launch(app, id) }, 300)
        // Kiểm tra: nếu cửa sổ không hiện (máy chặn), chuyển sang thông báo nhắc.
        handler.postDelayed({
            if (CaptureStore.lastShown(app) != id && CaptureStore.get(app, id) != null) {
                Log.w(TAG, "Không mở được cửa sổ ghi nhanh, dùng thông báo")
                notify(app, capture, headsUp = true)
            }
        }, 3000)
    }

    fun launch(ctx: Context, id: String?) {
        try {
            ctx.startActivity(QuickAddActivity.intent(ctx, id))
        } catch (e: Exception) {
            Log.w(TAG, "startActivity lỗi", e)
        }
    }

    private fun showBanner(ctx: Context, capture: JSONObject) {
        try {
            buildAndShowBanner(ctx, capture)
        } catch (e: Exception) {
            // Thẻ nổi chỉ là phụ trợ; lỗi không được chặn việc mở cửa sổ ghi nhanh.
            Log.w(TAG, "Không hiện được thẻ nổi", e)
        }
    }

    @SuppressLint("SetTextI18n")
    private fun buildAndShowBanner(ctx: Context, capture: JSONObject) {
        dismissBanner()
        val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as? WindowManager ?: return
        val dp = { v: Float -> TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, ctx.resources.displayMetrics).toInt() }
        val income = capture.optBoolean("income")
        val amount = capture.optLong("amount")
        val bank = with(CaptureStore) {
            BankApps.byKey(capture.str("bankKey"))?.name
                ?: BankApps.byPackage(capture.str("packageName"))?.name
        } ?: "Ngân hàng"

        val layout = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundResource(R.drawable.overlay_bg)
            setPadding(dp(16f), dp(10f), dp(16f), dp(10f))
            elevation = dp(6f).toFloat()
        }
        layout.addView(TextView(ctx).apply {
            text = "Sổ Thu Chi · $bank"
            setTextColor(0xCCFFFFFF.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        })
        layout.addView(TextView(ctx).apply {
            text = (if (income) "Thu +" else "Chi -") + formatMoney(amount) + "  ·  chạm để ghi"
            setTextColor(0xFFFFFFFF.toInt())
            setTypeface(typeface, Typeface.BOLD)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        })
        val id = capture.optString("id")
        layout.setOnClickListener {
            dismissBanner()
            launch(ctx, id)
        }

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            x = 0
            y = dp(36f)
            horizontalMargin = 0.04f
        }
        try {
            wm.addView(layout, params)
            bannerView = layout
            handler.removeCallbacks(removeBanner)
            handler.postDelayed(removeBanner, 6000)
        } catch (e: Exception) {
            Log.w(TAG, "Không hiện được thẻ nổi", e)
        }
    }

    fun dismissBanner() {
        val v = bannerView ?: return
        bannerView = null
        handler.removeCallbacks(removeBanner)
        try {
            val wm = v.context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            wm.removeView(v)
        } catch (e: Exception) {
            // đã bị gỡ
        }
    }

    // --------------------------------------------------------- Thông báo

    fun notificationId(captureId: String): Int = 7000 + (captureId.hashCode() and 0x0fffffff)

    private fun ensureChannels(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL_ALERT) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ALERT, "Giao dịch cần ghi chép", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Nhắc ghi chép khi phát hiện giao dịch ngân hàng"
                }
            )
        }
        if (nm.getNotificationChannel(CHANNEL_SILENT) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_SILENT, "Giao dịch chờ ghi (im lặng)", NotificationManager.IMPORTANCE_LOW)
            )
        }
    }

    fun notify(ctx: Context, capture: JSONObject, headsUp: Boolean) {
        try {
            ensureChannels(ctx)
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val id = capture.optString("id")
            val income = capture.optBoolean("income")
            val amount = capture.optLong("amount")
            val bank = with(CaptureStore) { BankApps.byKey(capture.str("bankKey"))?.name } ?: "Ngân hàng"
            val pi = PendingIntent.getActivity(
                ctx,
                notificationId(id),
                QuickAddActivity.intent(ctx, id),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val channel = if (headsUp) CHANNEL_ALERT else CHANNEL_SILENT
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(ctx, channel)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(ctx).setPriority(
                    if (headsUp) Notification.PRIORITY_HIGH else Notification.PRIORITY_LOW
                )
            }
            val content = with(CaptureStore) { capture.str("content") }
            builder
                .setSmallIcon(R.drawable.ic_stat_capture)
                .setContentTitle((if (income) "Thu +" else "Chi -") + formatMoney(amount) + " · " + bank)
                .setContentText(content ?: "Chạm để ghi chép – nói tên khoản chi")
                .setContentIntent(pi)
                .setAutoCancel(true)
                .setCategory(Notification.CATEGORY_REMINDER)
                .addAction(Notification.Action.Builder(null, "Ghi chép", pi).build())
            nm.notify(notificationId(id), builder.build())
        } catch (e: Exception) {
            Log.w(TAG, "Không gửi được thông báo", e)
        }
    }

    fun cancelNotification(ctx: Context, captureId: String) {
        try {
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(notificationId(captureId))
        } catch (e: Exception) {
            // bỏ qua
        }
    }

    fun cancelAll(ctx: Context, ids: List<String>) {
        ids.forEach { cancelNotification(ctx, it) }
    }

    /** Dùng khi Activity đã hiện: không cần thẻ nổi nữa. */
    fun onPopupShown(ctx: Context, captureId: String?) {
        dismissBanner()
        CaptureStore.markShown(ctx, captureId)
    }

    internal fun intentFlags(): Int =
        Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION
}
