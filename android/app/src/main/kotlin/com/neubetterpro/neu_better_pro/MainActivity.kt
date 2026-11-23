package com.neubetterpro.neu_better_pro

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.media.AudioAttributes
import android.content.Context
import android.content.ClipData
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileOutputStream
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val notificationPermissionRequestCode = 4201
    private var campusWifi: CampusWifiChannel? = null

    /** Flutter 就绪后建立的通道；点击通知时用它向 Dart 回调 openDorm。 */
    private var notificationChannel: MethodChannel? = null

    /** 冷启动时应用尚未开始监听，先把「待打开寝室用电」记下来等 Dart 来取。 */
    private var pendingOpenDorm = false

    /** 冷启动时待切换的一级标签（桌面小部件点击 -> 课表=1），-1 表示无。 */
    private var pendingOpenTab = -1

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ensureElectricityAlertChannel()
        ensurePluginNotifyChannel()
        requestNotificationPermissionIfNeeded()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        campusWifi = CampusWifiChannel(this, flutterEngine.dartExecutor.binaryMessenger)
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
                // 冷启动兜底：桌面小部件点击后待切换的一级标签。
                "getPendingOpenTab" -> {
                    val tab = pendingOpenTab
                    pendingOpenTab = -1
                    Log.d(LOG_TAG, "getPendingOpenTab -> $tab")
                    result.success(tab)
                }
                // 用系统默认浏览器打开外部链接（新闻「查看原文」等）。
                "openUrl" -> {
                    val url = call.argument<String>("url") ?: ""
                    try {
                        if (url.isNotEmpty()) {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                        }
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("open_url_failed", error.message, null)
                    }
                }
                // 插件/校园通知：使用 plugin_notify_v1 渠道发系统通知（带提示音）。
                "showPluginNotification" -> {
                    val title = call.argument<String>("title") ?: "通知"
                    val body = call.argument<String>("body") ?: ""
                    try {
                        showPluginNotification(title, body)
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("show_failed", error.message, null)
                    }
                }
                // 后台轮询「校园通知」：保存 personal cookie 与基线，并安排 15 分钟闹钟。
                "setBackgroundNotify" -> {
                    val cookie = call.argument<String>("cookie") ?: ""
                    val last = call.argument<Int>("last") ?: 0
                    try {
                        if (cookie.isEmpty()) {
                            NotifyPollPrefs.save(this, false, "", last)
                            NotifyPollScheduler.cancel(this)
                        } else {
                            NotifyPollPrefs.save(this, true, cookie, last)
                            NotifyPollScheduler.schedule(this)
                        }
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("bg_notify_failed", error.message, null)
                    }
                }
                "disableBackgroundNotify" -> {
                    try {
                        NotifyPollPrefs.setEnabled(this, false)
                        NotifyPollScheduler.cancel(this)
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("bg_notify_failed", error.message, null)
                    }
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
                            val status = installApk(path)
                            result.success(status)
                        } catch (error: Exception) {
                            result.error("install_failed", error.message, null)
                        }
                    }
                }
                // 是否已被允许安装未知来源应用（返回后据此自动续装）。
                "canInstallPackages" -> {
                    val allowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        packageManager.canRequestPackageInstalls()
                    } else {
                        true
                    }
                    result.success(allowed)
                }
                "openInstallPermission" -> {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName"),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    try {
                        startActivity(intent)
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("open_permission_failed", error.message, null)
                    }
                }
                // 打开安装包下载目录（App 内部 cache/neu_better_updates）。
                "openDownloadFolder" -> {
                    try {
                        openDownloadFolder()
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("open_folder_failed", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        // 桌面小部件：Dart 侧把课表数据推过来，存本地并刷新所有小部件。
        val widgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "neu_better/widget",
        )
        widgetChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    val payload = call.argument<String>("payload")
                    if (payload == null) {
                        result.error("bad_args", "payload is null", null)
                    } else {
                        TimetableWidgetData.store(this, payload)
                        WidgetUpdater.refreshAll(this)
                        result.success(true)
                    }
                }
                else -> result.notImplemented()
            }
        }
        // 文件保存：邮件附件写系统「下载」目录（Android 10+ 走 MediaStore）。
        val filesChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "neu_better/files",
        )
        filesChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToDownloads" -> {
                    val fileName = call.argument<String>("fileName")
                    val mime = call.argument<String>("mime") ?: "application/octet-stream"
                    val bytes = call.argument<ByteArray>("bytes")
                    if (fileName.isNullOrEmpty() || bytes == null) {
                        result.error("bad_args", "fileName/bytes is null", null)
                    } else {
                        try {
                            val path = saveToDownloads(fileName, mime, bytes)
                            result.success(path)
                        } catch (error: Exception) {
                            result.error("save_failed", error.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * 把字节保存到系统「下载」目录：Android 10+ 用 MediaStore.Downloads 插入
     * DISPLAY_NAME/MIME 再写入；<29 用公共 Downloads 目录（同名加 (1)）兜底。
     * 返回已保存文件的 URI 或绝对路径。
     */
    private fun saveToDownloads(fileName: String, mime: String, bytes: ByteArray): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, mime)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val collection = MediaStore.Downloads.getContentUri(
                MediaStore.VOLUME_EXTERNAL_PRIMARY,
            )
            val uri = contentResolver.insert(collection, values)
                ?: throw IllegalStateException("无法创建下载条目")
            val output = contentResolver.openOutputStream(uri)
                ?: throw IllegalStateException("无法打开下载输出流")
            output.use {
                it.write(bytes)
                it.flush()
            }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            return uri.toString()
        }
        val dir = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS,
        )
        if (!dir.exists()) dir.mkdirs()
        val dot = fileName.lastIndexOf('.')
        var target = File(dir, fileName)
        var index = 1
        while (target.exists()) {
            val candidate = if (dot > 0) {
                "${fileName.substring(0, dot)}($index)${fileName.substring(dot)}"
            } else {
                "$fileName($index)"
            }
            target = File(dir, candidate)
            index++
        }
        FileOutputStream(target).use { it.write(bytes) }
        return target.absolutePath
    }

    /**
     * 用 FileProvider 授权的 content:// 触发系统安装未知来源应用。
     *
     * 返回 "ok" 表示已拉起安装器；"need_permission" 表示用户尚未允许
     * 「安装未知应用」，此时跳转系统授权页，用户允许后需再次点击更新。
     */
    private fun installApk(path: String): String {        val file = File(path)
        require(file.exists() && file.length() > 0L) {
            "apk not found or empty: $path"
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            val settingsIntent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(settingsIntent)
            return "need_permission"
        }
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
            // 部分厂商 ROM 需要 clipData 才能把读权限一并授予安装器。
            clipData = ClipData.newRawUri("apk", uri)
        }
        try {
            startActivity(intent)
        } catch (first: Exception) {
            Log.w(LOG_TAG, "ACTION_VIEW install failed, fallback INSTALL_PACKAGE: ${first.message}")
            val fallback = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                data = uri
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                clipData = ClipData.newRawUri("apk", uri)
            }
            try {
                startActivity(fallback)
            } catch (second: Exception) {
                throw IllegalStateException(
                    "无法调起系统安装器：${second.message ?: second.javaClass.simpleName}",
                )
            }
        }
        return "ok"
    }

    /**
     * 打开安装包下载目录：安卓的安装包在 App 内部 cache/neu_better_updates，
     * 系统文件管理器无法直接定位到该内部目录，这里 Toast 出完整路径并尝试
     * 打开「文件」首页，便于用户知晓位置。
     */
    private fun openDownloadFolder() {
        val dir = File(cacheDir, "neu_better_updates")
        if (!dir.exists()) dir.mkdirs()
        val folderUri = try {
            FileProvider.getUriForFile(this, "$packageName.fileprovider", dir)
        } catch (_: Exception) {
            null
        }
        // 依次尝试目录 URI 的常见 MIME，系统/MT 管理器接受的类型不一致。
        // 只有确实存在可处理的应用时才弹选择器，否则会得到“没有应用可执行此操作”。
        val candidates = mutableListOf<Intent>()
        if (folderUri != null) {
            for (mime in listOf("resource/folder", "vnd.android.document/directory")) {
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(folderUri, mime)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    clipData = ClipData.newRawUri("folder", folderUri)
                }
                if (intent.resolveActivity(packageManager) != null) {
                    candidates.add(intent)
                    break
                }
            }
        }
        // 公共存储根目录（系统「文件」可处理），让用户至少能进系统文件管理器。
        val rootUri = Uri.parse("content://com.android.externalstorage.documents/root/primary")
        val rootIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(rootUri, "vnd.android.document/root")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        if (rootIntent.resolveActivity(packageManager) != null) {
            candidates.add(rootIntent)
        }
        if (candidates.isNotEmpty()) {
            val chooser = Intent.createChooser(candidates.first(), "选择打开方式").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(chooser)
            return
        }
        // 最后兜底：系统文档选择器一定能打开（用户可浏览本机存储）。
        Toast.makeText(this, "下载位置：${dir.absolutePath}", Toast.LENGTH_LONG).show()
        try {
            startActivity(
                Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (_: Exception) {
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        campusWifi?.onPermissionResult(requestCode)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        campusWifi?.close()
        campusWifi = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // 复用已有 Activity（singleTop）时更新当前 intent，再处理跳转。
        setIntent(intent)
        // 桌面小部件点击：切到课表一级标签（应用可能已在任意页面）。
        val tab = intent.getIntExtra(EXTRA_OPEN_TAB, -1)
        if (tab >= 0) {
            intent.removeExtra(EXTRA_OPEN_TAB)
            val channel = notificationChannel
            if (channel != null) {
                Log.d(LOG_TAG, "onNewIntent openTab -> invoke Dart $tab")
                channel.invokeMethod("openTab", tab)
            } else {
                Log.d(LOG_TAG, "onNewIntent openTab -> channel not ready, pending $tab")
                pendingOpenTab = tab
            }
        }
        val wantsOpenDorm = intent.getBooleanExtra(EXTRA_OPEN_DORM, false)
        if (wantsOpenDorm) {
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
    }

    /** 处理启动 intent：若带 openDorm extra，记为待处理并清掉 extra 防重复触发。 */
    private fun handleLaunchIntent(intent: Intent?) {
        if (intent == null) return
        val tab = intent.getIntExtra(EXTRA_OPEN_TAB, -1)
        if (tab >= 0) {
            pendingOpenTab = tab
            intent.removeExtra(EXTRA_OPEN_TAB)
            Log.d(LOG_TAG, "handleLaunchIntent openTab -> pending $tab (cold start)")
        }
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
            // 显式设置提示音：旧渠道（electricity_alert）曾因未设置 sound 而静音。
            setSound(
                Settings.System.DEFAULT_NOTIFICATION_URI,
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .build(),
            )
        }
        manager.createNotificationChannel(channel)
    }

    /** 创建插件/校园通知渠道（plugin_notify_v1）：IMPORTANCE_HIGH + 显式提示音。 */
    private fun ensurePluginNotifyChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(PLUGIN_CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            PLUGIN_CHANNEL_ID,
            "应用通知",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "校园通知、新邮件与插件消息的悬浮提醒"
            enableLights(true)
            enableVibration(true)
            setSound(
                Settings.System.DEFAULT_NOTIFICATION_URI,
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .build(),
            )
        }
        manager.createNotificationChannel(channel)
    }

    /** 发一条插件/校园通知悬浮通知；未授予通知权限时静默跳过。 */
    private fun showPluginNotification(title: String, body: String) {
        ensurePluginNotifyChannel()
        if (!hasNotificationPermission()) {
            return
        }
        val builder = NotificationCompat.Builder(this, PLUGIN_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setSilent(false)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
        NotificationManagerCompat.from(this)
            .notify(PLUGIN_NOTIFICATION_ID, builder.build())
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
            .setSilent(false)
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
        private const val ALERT_CHANNEL_ID = "electricity_alert_v2"
        private const val PLUGIN_CHANNEL_ID = "plugin_notify_v1"
        private const val ALERT_NOTIFICATION_ID = 0xE1EC
        private const val PLUGIN_NOTIFICATION_ID = 0xE1ED
        private const val EXTRA_OPEN_DORM = "openDorm"
        private const val EXTRA_OPEN_TAB = "openTab"
        private const val REQUEST_CODE_OPEN_DORM = 0x0D0E
        private const val LOG_TAG = "NEUNotify"
    }
}
