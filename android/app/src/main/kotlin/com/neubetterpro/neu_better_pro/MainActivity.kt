package com.neubetterpro.neu_better_pro

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val notificationPermissionRequestCode = 4201

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ensureElectricityAlertChannel()
        requestNotificationPermissionIfNeeded()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
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
                    else -> result.notImplemented()
                }
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
        NotificationManagerCompat.from(this).notify(ALERT_NOTIFICATION_ID, builder.build())
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
    }
}
