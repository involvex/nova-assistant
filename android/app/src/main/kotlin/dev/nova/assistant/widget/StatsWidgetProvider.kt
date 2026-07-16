package dev.nova.assistant.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import dev.nova.assistant.MainActivity
import dev.nova.assistant.R
import dev.nova.assistant.WidgetTrampolineActivity

class StatsWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val PREFS_NAME = "dev.nova.assistant.widget.stats"
        private const val KEY_TASKS_COUNT = "tasks_count"
        private const val KEY_NOTES_COUNT = "notes_count"
        private const val KEY_MEMORY_COUNT = "memory_count"

        private const val ACTION_OPEN_TASKS = "dev.nova.assistant.widget.ACTION_OPEN_TASKS"
        private const val ACTION_OPEN_NOTES = "dev.nova.assistant.widget.ACTION_OPEN_NOTES"
        private const val ACTION_OPEN_MEMORY = "dev.nova.assistant.widget.ACTION_OPEN_MEMORY"

        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            tasksCount: Int = 0,
            notesCount: Int = 0,
            memoryCount: Int = 0
        ) {
            val views = RemoteViews(context.packageName, R.layout.stats_widget)

            views.setTextViewText(R.id.text_tasks_count, tasksCount.toString())
            views.setTextViewText(R.id.text_notes_count, notesCount.toString())
            views.setTextViewText(R.id.text_memory_count, memoryCount.toString())

            views.setOnClickPendingIntent(R.id.stat_tasks, createPendingIntent(context, ACTION_OPEN_TASKS, 1))
            views.setOnClickPendingIntent(R.id.stat_notes, createPendingIntent(context, ACTION_OPEN_NOTES, 2))
            views.setOnClickPendingIntent(R.id.stat_memory, createPendingIntent(context, ACTION_OPEN_MEMORY, 3))
            views.setOnClickPendingIntent(R.id.widget_container, createPendingIntent(context, "tap", 0))

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun createPendingIntent(context: Context, action: String, requestCode: Int): PendingIntent {
            val intent = Intent(context, WidgetTrampolineActivity::class.java).apply {
                this.action = action
                data = Uri.parse("nova://widget/$action")
            }
            return PendingIntent.getActivity(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        fun getStatsFromPrefs(context: Context): Triple<Int, Int, Int> {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val tasks = prefs.getInt(KEY_TASKS_COUNT, 0)
            val notes = prefs.getInt(KEY_NOTES_COUNT, 0)
            val memory = prefs.getInt(KEY_MEMORY_COUNT, 0)
            return Triple(tasks, notes, memory)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val (tasks, notes, memory) = getStatsFromPrefs(context)
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId, tasks, notes, memory)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        // Only handle our own custom widget actions — ignore system broadcasts like APPWIDGET_UPDATE
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
    }

    override fun onEnabled(context: Context) {
    }

    override fun onDisabled(context: Context) {
    }
}