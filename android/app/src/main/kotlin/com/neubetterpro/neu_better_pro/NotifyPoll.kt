package com.neubetterpro.neu_better_pro

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject

/** 「校园通知」后台轮询的持久化状态（cookie / 上次未读数 / 是否启用）。 */
object NotifyPollPrefs {
    private const val NAME = "neu_notify_bg"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_COOKIE = "cookie"
    private const val KEY_LAST = "last"

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(NAME, Context.MODE_PRIVATE)

    fun enabled(ctx: Context): Boolean = prefs(ctx).getBoolean(KEY_ENABLED, false)
    fun cookie(ctx: Context): String = prefs(ctx).getString(KEY_COOKIE, "") ?: ""
    fun last(ctx: Context): Int = prefs(ctx).getInt(KEY_LAST, 0)

    fun save(ctx: Context, enabled: Boolean, cookie: String?, last: Int) {
        prefs(ctx).edit()
            .putBoolean(KEY_ENABLED, enabled)
            .putString(KEY_COOKIE, cookie ?: "")
            .putInt(KEY_LAST, last)
            .apply()
    }

    fun setLast(ctx: Context, last: Int) {
        prefs(ctx).edit().putInt(KEY_LAST, last).apply()
    }

    fun setEnabled(ctx: Context, enabled: Boolean) {
        prefs(ctx).edit().putBoolean(KEY_ENABLED, enabled).apply()
    }
}

/** 15 分钟一次的不精确闹钟（省电、无额外依赖）；重启后由 NotifyBootReceiver 恢复。 */
object NotifyPollScheduler {
    private const val REQUEST_CODE = 0x51
    private const val INTERVAL_MS = 15 * 60 * 1000L

    private fun pending(ctx: Context): PendingIntent {
        val intent = Intent(ctx, NotifyPollReceiver::class.java)
        return PendingIntent.getBroadcast(
            ctx,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun schedule(ctx: Context) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        am.setInexactRepeating(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            SystemClock.elapsedRealtime() + INTERVAL_MS,
            INTERVAL_MS,
            pending(ctx),
        )
        Log.d("NEUNotify", "background poll scheduled")
    }

    fun cancel(ctx: Context) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        am.cancel(pending(ctx))
        Log.d("NEUNotify", "background poll canceled")
    }

    fun rescheduleIfEnabled(ctx: Context) {
        if (NotifyPollPrefs.enabled(ctx) && NotifyPollPrefs.cookie(ctx).isNotEmpty()) {
            schedule(ctx)
        } else {
            cancel(ctx)
        }
    }
}

/** 闹钟到点：后台拉取未读统计，若未读增加则发系统通知。 */
class NotifyPollReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!NotifyPollPrefs.enabled(context)) return
        val cookie = NotifyPollPrefs.cookie(context)
        if (cookie.isEmpty()) return
        val pending = goAsync()
        Thread {
            try {
                poll(context, cookie)
            } catch (error: Exception) {
                Log.w("NEUNotify", "background poll failed: $error")
            } finally {
                pending.finish()
            }
        }.start()
    }

    private fun poll(context: Context, cookie: String) {
        val url = URL("https://personal.neu.edu.cn/portal/ucs/frontend/msg/countData")
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 15000
            readTimeout = 20000
            setRequestProperty("Cookie", cookie)
            setRequestProperty("X-Requested-With", "XMLHttpRequest")
            setRequestProperty("Referer", "https://personal.neu.edu.cn/portal/ucs/pages/ucs/site/messageCenter/home?type=3")
            setRequestProperty(
                "User-Agent",
                "Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 Chrome/157.0.0.0 Mobile Safari/537.36",
            )
        }
        val text = try {
            conn.inputStream.bufferedReader().use { it.readText() }
        } finally {
            conn.disconnect()
        }
        val noRead = JSONObject(text)
            .optJSONObject("d")
            ?.optInt("noReadCount", -1) ?: -1
        if (noRead < 0) return
        val last = NotifyPollPrefs.last(context)
        if (noRead > last) {
            showNotification(context, noRead)
        }
        NotifyPollPrefs.setLast(context, noRead)
    }

    private fun showNotification(context: Context, noRead: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            manager.getNotificationChannel(PLUGIN_CHANNEL_ID) == null
        ) {
            val channel = NotificationChannel(
                PLUGIN_CHANNEL_ID,
                "应用通知",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                enableVibration(true)
                setSound(
                    android.provider.Settings.System.DEFAULT_NOTIFICATION_URI,
                    android.media.AudioAttributes.Builder()
                        .setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION)
                        .build(),
                )
            }
            manager.createNotificationChannel(channel)
        }
        val launch = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val contentIntent = PendingIntent.getActivity(
            context,
            0x52,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(context, PLUGIN_CHANNEL_ID)
            .setContentTitle("你有 $noRead 条未读通知")
            .setContentText("点开查看校园消息与待办")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setSilent(false)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
        NotificationManagerCompat.from(context).notify(0xE1EF, builder.build())
    }

    companion object {
        private const val PLUGIN_CHANNEL_ID = "plugin_notify_v1"
    }
}

/** 开机后恢复已启用的后台轮询。 */
class NotifyBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            NotifyPollScheduler.rescheduleIfEnabled(context)
        }
    }
}
