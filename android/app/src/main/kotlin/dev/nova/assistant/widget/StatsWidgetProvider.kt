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

class StatsWidgetProvider : AppWidgetProvider() {

    companion object {
        const val PREFS_NAME = "dev.nova.assistant.widget.stats"
        const val KEY_TASKS_COUNT = "tasks_count"
        const val KEY_NOTES_COUNT = "notes_count"
        const val KEY_MEMORY_COUNT = "memory_count"

        const val ACTION_OPEN_TASKS = "dev.nova.assistant.widget.ACTION_OPEN_TASKS"
        const val ACTION_OPEN_NOTES = "dev.nova.assistant.widget.ACTION_OPEN_NOTES"
        const val ACTION_OPEN_MEMORY = "dev.nova.assistant.widget.ACTION_OPEN_MEMORY"

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
            val intent = Intent(context, MainActivity::class.java).apply {
                this.action = action
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
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

        val action = intent.action
        if (action == ACTION_OPEN_TASKS || action == ACTION_OPEN_NOTES || action == ACTION_OPEN_MEMORY || action == "tap") {
            val targetIntent = Intent(context, MainActivity::class.java).apply {
                this.action = action
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                data = Uri.parse("nova://widget/$action")
            }
            context.startActivity(targetIntent)
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        // Clean up if needed
    }

    override fun onEnabled(context: Context) {
        // First widget added
    }

    override fun onDisabled(context: Context) {
        // Last widget removed
    }
}