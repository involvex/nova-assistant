package dev.nova.assistant

import android.app.Activity
import android.content.Intent
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import java.io.File

/**
 * MainActivity — the primary Flutter activity for Nova.
 * Also handles launching from the assistant button via Intent extras
 * and receiving shared text/URLs via ACTION_SEND.
 *
 * All platform-channel registrations have been moved to [NovaChannelRegistrar].
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "NovaMain"
        private const val REQUEST_SCREEN_CAPTURE = 1001
        private const val REQUEST_ASSISTANT_ROLE = 1002
        private const val WIDGET_ACTION_KEY = "home_widget_action"
        const val WIDGET_PREFS_NAME = "HomeWidgetPreferences"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        NovaChannelRegistrar.registerWith(flutterEngine, this)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return

        if (intent.action == Intent.ACTION_SEND) {
            NovaChannelRegistrar.handleShareIntent(this, intent)
            return
        }

        val dataString = intent.dataString ?: return
        if (dataString.startsWith("nova://widget/")) {
            val action = dataString.removePrefix("nova://widget/")
            if (action.startsWith("android.")) return
            Log.d(TAG, "Widget action received: $action")
            val prefs = getSharedPreferences(WIDGET_PREFS_NAME, 0)
            prefs.edit().putString(WIDGET_ACTION_KEY, action).apply()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)

        handleIntent(intent)

        try {
            val screenshotPath = intent.getStringExtra(AssistantActivity.EXTRA_SCREENSHOT_PATH)
            val screenText = intent.getStringExtra(AssistantActivity.EXTRA_SCREEN_TEXT)
            val timestamp = intent.getLongExtra(AssistantActivity.EXTRA_TIMESTAMP, 0L)

            Log.d(TAG, "onCreate: screenshotPath=$screenshotPath, screenText=$screenText, timestamp=$timestamp")

            if (screenshotPath != null) {
                AssistantActivity.isSystemAssistantLaunch = true
                val file = File(screenshotPath)
                if (file.exists()) {
                    try {
                        val bytes = file.readBytes()
                        AssistantActivity.latestScreenshot = bytes
                        AssistantActivity.latestScreenText = screenText
                        AssistantActivity.latestTimestamp = timestamp
                        Log.d(TAG, "Screenshot loaded from file: ${bytes.size} bytes")
                        file.delete()
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to read screenshot file: ${e.message}")
                    }
                } else {
                    Log.w(TAG, "Screenshot file does not exist: $screenshotPath")
                }
            } else {
                Log.d(TAG, "No screenshot path in intent")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in onCreate: ${e.message}")
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQUEST_SCREEN_CAPTURE,
            ScreenCaptureHelper.REQUEST_SCREEN_CAPTURE -> {
                val granted = resultCode == Activity.RESULT_OK && data != null
                if (granted && data != null) {
                    Log.d(TAG, "Screen capture permission granted")
                    ScreenCaptureHelper.startCapture(this, data)
                    ScreenCaptureHelper.onScreenCapturePermissionResult(true)
                } else {
                    Log.d(TAG, "Screen capture permission denied")
                    ScreenCaptureHelper.onScreenCapturePermissionResult(false)
                }
            }
            REQUEST_ASSISTANT_ROLE -> {
                Log.d(TAG, "Assistant role request done")
            }
        }
    }
}
