package dev.nova.assistant.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import android.widget.RemoteViews.RemoteView
import dev.nova.assistant.MainActivity
import dev.nova.assistant.R

class QuickActionsWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_NEW_CHAT = "dev.nova.assistant.widget.ACTION_NEW_CHAT"
        const val ACTION_VOICE = "dev.nova.assistant.widget.ACTION_VOICE"
        const val ACTION_SCREENSHOT = "dev.nova.assistant.widget.ACTION_SCREENSHOT"
        const val ACTION_QUICK_ASK = "dev.nova.assistant.widget.ACTION_QUICK_ASK"

        private const val ACTION_PREFIX = "dev.nova.assistant.widget.ACTION_"

        fun updateWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.quick_actions_widget)

            val clickIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }

            views.setOnClickPendingIntent(R.id.btn_new_chat, createPendingIntent(context, ACTION_NEW_CHAT))
            views.setOnClickPendingIntent(R.id.btn_voice, createPendingIntent(context, ACTION_VOICE))
            views.setOnClickPendingIntent(R.id.btn_screenshot, createPendingIntent(context, ACTION_SCREENSHOT))
            views.setOnClickPendingIntent(R.id.btn_quick_ask, createPendingIntent(context, ACTION_QUICK_ASK))

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun createPendingIntent(context: Context, action: String): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                this.action = action
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
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

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)

        val action = intent.action ?: return

        if (action.startsWith(ACTION_PREFIX)) {
            val targetIntent = Intent(context, MainActivity::class.java).apply {
                this.action = action
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                data = Uri.parse("nova://widget/$action")
            }
            context.startActivity(targetIntent)
        }
    }

    override fun onEnabled(context: Context) {
        // First widget added
    }

    override fun onDisabled(context: Context) {
        // Last widget removed
    }
}