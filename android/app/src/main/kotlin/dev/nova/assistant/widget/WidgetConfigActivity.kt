package dev.nova.assistant.widget

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.CheckBox
import dev.nova.assistant.R

class WidgetConfigActivity : Activity() {

    companion object {
        const val PREFS_NAME = "dev.nova.assistant.widget.config"
        const val KEY_SHOW_NEW_CHAT = "show_new_chat"
        const val KEY_SHOW_VOICE = "show_voice"
        const val KEY_SHOW_SCREENSHOT = "show_screenshot"
        const val KEY_SHOW_QUICK_ASK = "show_quick_ask"

        private const val EXTRA_APPWIDGET_ID = "appWidgetId"

        fun getDefaultSelectedActions(): Set<String> = setOf(
            KEY_SHOW_NEW_CHAT,
            KEY_SHOW_VOICE,
            KEY_SHOW_SCREENSHOT,
            KEY_SHOW_QUICK_ASK
        )
    }

    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    private lateinit var checkNewChat: CheckBox
    private lateinit var checkVoice: CheckBox
    private lateinit var checkScreenshot: CheckBox
    private lateinit var checkQuickAsk: CheckBox

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setResult(RESULT_CANCELED)

        appWidgetId = intent.getIntExtra(EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        setContentView(R.layout.widget_config_activity)

        checkNewChat = findViewById(R.id.check_new_chat)
        checkVoice = findViewById(R.id.check_voice)
        checkScreenshot = findViewById(R.id.check_screenshot)
        checkQuickAsk = findViewById(R.id.check_quick_ask)

        val btnSave: Button = findViewById(R.id.btn_save)
        val btnCancel: Button = findViewById(R.id.btn_cancel)

        btnSave.setOnClickListener { onSaveClicked() }
        btnCancel.setOnClickListener { onCancelClicked() }

        loadCurrentConfig()
    }

    private fun loadCurrentConfig() {
        val widgetPrefs = getSharedPreferences("${PREFS_NAME}_$appWidgetId", MODE_PRIVATE)

        checkNewChat.isChecked = widgetPrefs.getBoolean(KEY_SHOW_NEW_CHAT, true)
        checkVoice.isChecked = widgetPrefs.getBoolean(KEY_SHOW_VOICE, true)
        checkScreenshot.isChecked = widgetPrefs.getBoolean(KEY_SHOW_SCREENSHOT, true)
        checkQuickAsk.isChecked = widgetPrefs.getBoolean(KEY_SHOW_QUICK_ASK, true)
    }

    private fun onSaveClicked() {
        val widgetPrefs = getSharedPreferences("${PREFS_NAME}_$appWidgetId", MODE_PRIVATE).edit()

        widgetPrefs.putBoolean(KEY_SHOW_NEW_CHAT, checkNewChat.isChecked)
        widgetPrefs.putBoolean(KEY_SHOW_VOICE, checkVoice.isChecked)
        widgetPrefs.putBoolean(KEY_SHOW_SCREENSHOT, checkScreenshot.isChecked)
        widgetPrefs.putBoolean(KEY_SHOW_QUICK_ASK, checkQuickAsk.isChecked)
        widgetPrefs.apply()

        val appWidgetManager = AppWidgetManager.getInstance(this)
        QuickActionsWidgetProvider.updateWidget(this, appWidgetManager, appWidgetId)

        val resultValue = Intent().apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        }
        setResult(RESULT_OK, resultValue)
        finish()
    }

    private fun onCancelClicked() {
        finish()
    }
}