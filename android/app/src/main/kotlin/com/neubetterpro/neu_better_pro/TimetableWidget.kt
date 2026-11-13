package com.neubetterpro.neu_better_pro

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/** 供桌面小部件使用的今日课程数据模型。 */
data class WidgetItem(
    val name: String,
    val room: String,
    val teacher: String,
    val start: String,
    val end: String,
    val isExam: Boolean,
    val startMinutes: Int,
    val endMinutes: Int,
)

object TimetableWidgetData {
    private const val PREFS = "neu_widget_prefs"
    private const val KEY = "payload"
    private val dateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)

    fun store(context: Context, payload: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY, payload).apply()
    }

    private fun load(context: Context): String? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY, null)

    /** 两行要显示的内容。 */
    data class Lines(
        val first: WidgetItem?,
        val second: WidgetItem?,
        val firstActive: Boolean,
        val secondActive: Boolean,
        val emptyText: String?,
    )

    fun compute(context: Context): Lines {
        val payload = load(context) ?: return Lines(null, null, false, false, "打开应用同步课程")
        return try {
            computeFrom(payload, Calendar.getInstance())
        } catch (e: Exception) {
            Lines(null, null, false, false, "今日课程已结束")
        }
    }

    fun computeFrom(payload: String, now: Calendar): Lines {
        val root = JSONObject(payload)
        val anchorRaw = root.optString("anchorDate")
        val anchorWeek = root.optInt("anchorWeek", 1)
        val anchor = dateFormat.parse(anchorRaw)
            ?: return Lines(null, null, false, false, "今日课程已结束")

        val todayCal = Calendar.getInstance().apply {
            timeInMillis = now.timeInMillis
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val anchorCal = Calendar.getInstance().apply {
            time = anchor
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val diffDays = ((todayCal.timeInMillis - anchorCal.timeInMillis) / 86400000L).toInt()
        val week = anchorWeek + Math.floorDiv(diffDays, 7)
        // Calendar.SUNDAY=1..SATURDAY=7 → ISO 周一=1..周日=7
        val isoDow = ((now.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1
        val todayStr = dateFormat.format(now.time)
        val nowMinutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)

        val items = ArrayList<WidgetItem>()

        val courses = root.optJSONArray("courses") ?: JSONArray()
        for (i in 0 until courses.length()) {
            val o = courses.getJSONObject(i)
            if (o.optInt("day") != isoDow) continue
            val weeks = o.optJSONArray("weeks") ?: continue
            var active = false
            for (j in 0 until weeks.length()) {
                if (weeks.getInt(j) == week) { active = true; break }
            }
            if (!active) continue
            val start = o.optString("startTime")
            val end = o.optString("endTime")
            val sm = parseMinutes(start) ?: continue
            val em = parseMinutes(end) ?: (sm + 45)
            items.add(
                WidgetItem(
                    o.optString("name"), o.optString("room"), o.optString("teacher"),
                    start, end, false, sm, em,
                ),
            )
        }

        val exams = root.optJSONArray("exams") ?: JSONArray()
        for (i in 0 until exams.length()) {
            val o = exams.getJSONObject(i)
            if (o.optString("date") != todayStr) continue
            val start = o.optString("startTime")
            val end = o.optString("endTime")
            val sm = parseMinutes(start) ?: continue
            val em = parseMinutes(end) ?: (sm + 60)
            items.add(
                WidgetItem(
                    o.optString("name"), o.optString("room"), o.optString("teacher"),
                    start, end, true, sm, em,
                ),
            )
        }

        items.sortBy { it.startMinutes }

        val current = items.firstOrNull { nowMinutes >= it.startMinutes && nowMinutes < it.endMinutes }
        if (current != null) {
            val next = items.firstOrNull { it.startMinutes > nowMinutes }
            return Lines(current, next, true, false, null)
        }
        val upcoming = items.filter { it.startMinutes > nowMinutes }
        return if (upcoming.isNotEmpty()) {
            Lines(upcoming.getOrNull(0), upcoming.getOrNull(1), false, false, null)
        } else {
            Lines(null, null, false, false, "今日课程已结束")
        }
    }

    private fun parseMinutes(raw: String): Int? {
        val match = Regex("(\\d{1,2}):(\\d{2})").find(raw) ?: return null
        return match.groupValues[1].toInt() * 60 + match.groupValues[2].toInt()
    }
}

/** 刷新所有已放置的课程小部件（数据更新后调用）。 */
object WidgetUpdater {
    fun refreshAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val classes = listOf(
            TimetableWidget2x2Provider::class.java,
            TimetableWidget2x4Provider::class.java,
        )
        for (clazz in classes) {
            val ids = manager.getAppWidgetIds(ComponentName(context, clazz))
            if (ids.isEmpty()) continue
            val intent = Intent(context, clazz).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            }
            context.sendBroadcast(intent)
        }
    }
}

abstract class BaseTimetableWidgetProvider : AppWidgetProvider() {
    protected abstract fun layoutId(): Int

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) render(context, appWidgetManager, id)
    }

    private fun render(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
    ) {
        val views = RemoteViews(context.packageName, layoutId())
        val lines = TimetableWidgetData.compute(context)
        val blue = 0xFF0B4F9C.toInt()
        val ink = 0xFF14243B.toInt()
        val muted = 0xFF5D7392.toInt()

        if (lines.emptyText != null) {
            views.setTextViewText(R.id.widget_line1, lines.emptyText)
            views.setTextColor(R.id.widget_line1, muted)
            views.setTextViewText(R.id.widget_line2, "")
        } else {
            bindLine(views, R.id.widget_line1, lines.first, lines.firstActive, blue, ink)
            bindLine(views, R.id.widget_line2, lines.second, lines.secondActive, blue, muted)
        }

        val launch = Intent(context, MainActivity::class.java)
        val pending = PendingIntent.getActivity(
            context,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.widget_root, pending)
        manager.updateAppWidget(widgetId, views)
    }

    private fun bindLine(
        views: RemoteViews,
        viewId: Int,
        item: WidgetItem?,
        active: Boolean,
        activeColor: Int,
        normalColor: Int,
    ) {
        if (item == null) {
            views.setTextViewText(viewId, "")
            return
        }
        val meta = ArrayList<String>()
        if (item.room.isNotEmpty()) meta.add(item.room)
        if (item.teacher.isNotEmpty()) meta.add(item.teacher)
        if (item.start.isNotEmpty() || item.end.isNotEmpty()) {
            meta.add(item.start + "-" + item.end)
        }
        val head = if (active) "● 上课中  " + item.name else item.name
        val text = if (meta.isEmpty()) head else head + "\n" + meta.joinToString(" · ")
        views.setTextViewText(viewId, text)
        views.setTextColor(viewId, if (active) activeColor else normalColor)
    }
}

class TimetableWidget2x2Provider : BaseTimetableWidgetProvider() {
    override fun layoutId(): Int = R.layout.widget_timetable_2x2
}

class TimetableWidget2x4Provider : BaseTimetableWidgetProvider() {
    override fun layoutId(): Int = R.layout.widget_timetable_2x4
}
