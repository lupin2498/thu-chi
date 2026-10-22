package vn.sothuchi.so_thu_chi.capture

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Kênh `vn.sothuchi/capture` dùng chung cho MainActivity và QuickAddActivity. */
class CaptureChannelHandler(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val popup: QuickAddActivity? = null,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val handler = Handler(Looper.getMainLooper())
    private val ctx: Context get() = activity.applicationContext

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    fun sendNewCapture(map: Map<String, Any?>) {
        channel.invokeMethod("onNewCapture", map)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getPermissions" -> result.success(permissions())
                "openNotificationListenerSettings" -> {
                    openNotificationListenerSettings()
                    result.success(null)
                }
                "openOverlaySettings" -> {
                    startSafely(
                        Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${ctx.packageName}"))
                    ) || startSafely(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION))
                    result.success(null)
                }
                "openAppSettings" -> {
                    openAppSettings()
                    result.success(null)
                }
                "openBackgroundPopupSettings" -> result.success(openBackgroundPopupSettings())
                "requestPostNotifications" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                    ) {
                        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4101)
                        result.success(false)
                    } else {
                        if (!notificationsEnabled()) openAppSettings()
                        result.success(notificationsEnabled())
                    }
                }
                "requestMicrophone" -> {
                    if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                        if (activity.shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO) ||
                            !askedBefore(Manifest.permission.RECORD_AUDIO)
                        ) {
                            rememberAsked(Manifest.permission.RECORD_AUDIO)
                            activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 4102)
                        } else {
                            // Đã bị từ chối vĩnh viễn -> mở trang cài đặt ứng dụng.
                            openAppSettings()
                        }
                        result.success(false)
                    } else {
                        result.success(true)
                    }
                }
                "getSettings" -> result.success(CaptureStore.settings(ctx).toMap())
                "setSettings" -> {
                    val m = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                    CaptureStore.saveSettings(ctx, CaptureStore.Settings.fromMap(m))
                    result.success(null)
                }
                "getPendingCaptures" -> result.success(CaptureStore.pending(ctx).map { CaptureStore.toMap(it) })
                "removeCapture" -> {
                    val id = call.argument<String>("id")
                    if (id != null) {
                        CaptureStore.remove(ctx, id)
                        CapturePresenter.cancelNotification(ctx, id)
                    }
                    result.success(null)
                }
                "clearCaptures" -> {
                    val ids = CaptureStore.pending(ctx).map { it.optString("id") }
                    CaptureStore.clear(ctx)
                    CapturePresenter.cancelAll(ctx, ids)
                    result.success(null)
                }
                "getLaunchCapture" -> {
                    val id = popup?.currentCaptureId()
                    result.success(CaptureStore.get(ctx, id)?.let { CaptureStore.toMap(it) })
                }
                "closePopup" -> {
                    if (popup != null) {
                        popup.finish()
                        @Suppress("DEPRECATION")
                        popup.overridePendingTransition(0, android.R.anim.fade_out)
                    }
                    result.success(null)
                }
                "simulateNotification" -> {
                    val title = call.argument<String>("title")
                    val text = call.argument<String>("text").orEmpty()
                    val pkg = call.argument<String>("package") ?: "com.mbmobile"
                    if (!CaptureStore.settings(ctx).enabled) {
                        result.success("disabled")
                    } else if (BankParser.parse(text, title, pkg, false) == null) {
                        result.success("ignored")
                    } else {
                        // Trễ 3 giây để người dùng kịp về màn hình khác xem cửa sổ nổi.
                        handler.postDelayed({
                            CaptureProcessor.process(ctx, pkg, title, text, strict = false, dedupe = false)
                        }, 3000)
                        result.success("scheduled")
                    }
                }
                "getInstalledBankPackages" -> result.success(installedBankPackages())
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("capture_error", e.message, null)
        }
    }

    private fun permissions(): Map<String, Boolean> = mapOf(
        "notificationListener" to isListenerEnabled(ctx),
        "overlay" to Settings.canDrawOverlays(ctx),
        "postNotifications" to notificationsEnabled(),
        "microphone" to (ctx.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED),
    )

    private fun notificationsEnabled(): Boolean {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (!nm.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= 33) {
            return ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        }
        return true
    }

    private fun openNotificationListenerSettings() {
        val component = ComponentName(ctx, BankNotificationListener::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val i = Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                .putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, component.flattenToString())
            if (startSafely(i)) return
        }
        startSafely(Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")) || openAppSettings()
    }

    private fun openAppSettings(): Boolean =
        startSafely(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${ctx.packageName}")))

    /** Trang quyền riêng của Xiaomi / Oppo / Vivo (bật cửa sổ bật lên khi chạy nền). */
    private fun openBackgroundPopupSettings(): Boolean {
        val pkg = ctx.packageName
        val candidates = listOf(
            Intent("miui.intent.action.APP_PERM_EDITOR")
                .setClassName("com.miui.securitycenter", "com.miui.permcenter.permissions.PermissionsEditorActivity")
                .putExtra("extra_pkgname", pkg),
            Intent("miui.intent.action.APP_PERM_EDITOR")
                .setClassName("com.miui.securitycenter", "com.miui.permcenter.permissions.AppPermissionsEditorActivity")
                .putExtra("extra_pkgname", pkg),
            Intent().setClassName("com.coloros.safecenter", "com.coloros.safecenter.permission.floatwindow.FloatWindowListActivity"),
            Intent().setClassName("com.oplus.safecenter", "com.oplus.safecenter.permission.floatwindow.FloatWindowListActivity"),
            Intent().setClassName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.SoftPermissionDetailActivity")
                .putExtra("packagename", pkg),
            Intent().setClassName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.FloatWindowManager"),
        )
        for (i in candidates) {
            if (startSafely(i)) return true
        }
        return false
    }

    private fun startSafely(intent: Intent): Boolean {
        return try {
            activity.startActivity(intent)
            true
        } catch (e: Exception) {
            // ActivityNotFoundException / SecurityException (trang riêng của hãng không tồn tại)
            false
        }
    }

    private fun askedBefore(permission: String): Boolean =
        ctx.getSharedPreferences("sothuchi_perm", Context.MODE_PRIVATE).getBoolean(permission, false)

    private fun rememberAsked(permission: String) {
        ctx.getSharedPreferences("sothuchi_perm", Context.MODE_PRIVATE).edit().putBoolean(permission, true).apply()
    }

    private fun installedBankPackages(): List<String> {
        val pm = ctx.packageManager
        val out = ArrayList<String>()
        for (b in BankApps.all) {
            for (p in b.packages) {
                try {
                    @Suppress("DEPRECATION")
                    pm.getPackageInfo(p, 0)
                    out.add(p)
                } catch (e: PackageManager.NameNotFoundException) {
                    // chưa cài
                }
            }
        }
        return out
    }

    companion object {
        const val CHANNEL = "vn.sothuchi/capture"

        fun isListenerEnabled(ctx: Context): Boolean {
            val component = ComponentName(ctx, BankNotificationListener::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                return nm.isNotificationListenerAccessGranted(component)
            }
            val flat = Settings.Secure.getString(ctx.contentResolver, "enabled_notification_listeners") ?: return false
            return flat.split(":").any { ComponentName.unflattenFromString(it) == component }
        }
    }
}
