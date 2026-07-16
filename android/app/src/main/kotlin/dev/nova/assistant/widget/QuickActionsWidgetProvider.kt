package dev.nova.assistant.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import dev.nova.assistant.MainActivity
import dev.nova.assistant.R
import dev.nova.assistant.WidgetTrampolineActivity

class QuickActionsWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val ACTION_NEW_CHAT = "dev.nova.assistant.widget.ACTION_NEW_CHAT"
        private const val ACTION_VOICE = "dev.nova.assistant.widget.ACTION_VOICE"
        private const val ACTION_SCREENSHOT = "dev.nova.assistant.widget.ACTION_SCREENSHOT"
        private const val ACTION_QUICK_ASK = "dev.nova.assistant.widget.ACTION_QUICK_ASK"

        fun updateWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.quick_actions_widget)

            views.setOnClickPendingIntent(R.id.btn_new_chat, createPendingIntent(context, ACTION_NEW_CHAT))
            views.setOnClickPendingIntent(R.id.btn_voice, createPendingIntent(context, ACTION_VOICE))
            views.setOnClickPendingIntent(R.id.btn_screenshot, createPendingIntent(context, ACTION_SCREENSHOT))
            views.setOnClickPendingIntent(R.id.btn_quick_ask, createPendingIntent(context, ACTION_QUICK_ASK))

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun createPendingIntent(context: Context, action: String): PendingIntent {
            val intent = Intent(context, WidgetTrampolineActivity::class.java).apply {
                this.action = action
                data = Uri.parse("nova://widget/$action")
            }
            return PendingIntent.getActivity(
                context,
                action.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onEnabled(context: Context) {
    }

    override fun onDisabled(context: Context) {
    }
}