package com.neubetterpro.neu_better_pro

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val notificationPermissionRequestCode = 4201

    /** Flutter 就绪后建立的通道；点击通知时用它向 Dart 回调 openDorm。 */
    private var notificationChannel: MethodChannel? = null

    /** 冷启动时应用尚未开始监听，先把「待打开寝室用电」记下来等 Dart 来取。 */
    private var pendingOpenDorm = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ensureElectricityAlertChannel()
        requestNotificationPermissionIfNeeded()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 冷启动：若 Activity 由「点击用电提醒通知」拉起，先记下待处理请求，
        // 等 Dart 侧 HomePage 就绪后通过 getPendingOpenDorm 取走。
        handleLaunchIntent(intent)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        notificationChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "showElectricityAlert" -> {
                    val title = call.argument<String>("title") ?: "寝室电量不足"
                    val body = call.argument<String>("body") ?: ""
                    try {
                        showElectricityAlert(title, body)
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("show_failed", error.message, null)
                    }
                }
                // 冷启动兜底：取走待处理请求并复位，避免重复跳转。
                "getPendingOpenDorm" -> {
                    val pending = pendingOpenDorm
                    pendingOpenDorm = false
                    Log.d(LOG_TAG, "getPendingOpenDorm -> $pending")
                    result.success(pending)
                }
                else -> result.notImplemented()
            }
        }
        // 自动更新：把下载好的 apk 交给系统安装器。
        val updaterChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "neu_better/updater",
        )
        updaterChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.error("bad_args", "path is null", null)
                    } else {
                        try {
                            installApk(path)
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("install_failed", error.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** 用 FileProvider 授权的 content:// 触发系统安装未知来源应用。 */
    private fun installApk(path: String) {
        val file = File(path)
        require(file.exists()) { "apk not found: $path" }
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // 复用已有 Activity（singleTop）时更新当前 intent，再处理跳转。
        setIntent(intent)
        val wantsOpenDorm = intent.getBooleanExtra(EXTRA_OPEN_DORM, false)
        if (!wantsOpenDorm) return
        intent.removeExtra(EXTRA_OPEN_DORM)
        val channel = notificationChannel
        if (channel != null) {
            // 应用已在运行：直接回调 Dart 切到寝室用电页。
            Log.d(LOG_TAG, "onNewIntent openDorm -> invoke Dart openDorm")
            channel.invokeMethod("openDorm", null)
        } else {
            Log.d(LOG_TAG, "onNewIntent openDorm -> channel not ready, mark pending")
            pendingOpenDorm = true
        }
    }

    /** 处理启动 intent：若带 openDorm extra，记为待处理并清掉 extra 防重复触发。 */
    private fun handleLaunchIntent(intent: Intent?) {
        if (intent == null) return
        if (intent.getBooleanExtra(EXTRA_OPEN_DORM, false)) {
            pendingOpenDorm = true
            intent.removeExtra(EXTRA_OPEN_DORM)
            Log.d(LOG_TAG, "handleLaunchIntent openDorm -> mark pending (cold start)")
        }
    }

    /** 创建 IMPORTANCE_HIGH 的用电提醒渠道：允许横幅（heads-up）、声音与震动。 */
    private fun ensureElectricityAlertChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(ALERT_CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            ALERT_CHANNEL_ID,
            "用电提醒",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "寝室电量低于提醒线时的悬浮提醒"
            enableLights(true)
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 400, 200, 400)
        }
        manager.createNotificationChannel(channel)
    }

    /** 发一条用电提醒悬浮通知；未授予通知权限时静默跳过（应用内弹窗仍兜底）。 */
    private fun showElectricityAlert(title: String, body: String) {
        ensureElectricityAlertChannel()
        if (!hasNotificationPermission()) {
            return
        }
        val builder = NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setContentIntent(buildOpenDormPendingIntent())
        NotificationManagerCompat.from(this).notify(ALERT_NOTIFICATION_ID, builder.build())
    }

    /** 点击通知 → 复用/拉起 MainActivity 并带上 openDorm extra。 */
    private fun buildOpenDormPendingIntent(): PendingIntent {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_OPEN_DORM, true)
        }
        return PendingIntent.getActivity(
            this,
            REQUEST_CODE_OPEN_DORM,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun hasNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    /** Android 13+ 需要 POST_NOTIFICATIONS 运行时权限，未授予时在启动时申请一次。 */
    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (hasNotificationPermission()) return
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode,
        )
    }

    companion object {
        /** 与 Dart 侧 AndroidHeadsUpChannel.channel 名称一致。 */
        private const val CHANNEL_NAME = "neu_better/notifications"
        private const val ALERT_CHANNEL_ID = "electricity_alert"
        private const val ALERT_NOTIFICATION_ID = 0xE1EC
        private const val EXTRA_OPEN_DORM = "openDorm"
        private const val REQUEST_CODE_OPEN_DORM = 0x0D0E
        private const val LOG_TAG = "NEUNotify"
    }
}
