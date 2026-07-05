package dev.nova.assistant

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * MainActivity — the primary Flutter activity for Nova.
 * Also handles launching from the assistant button via Intent extras.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val REQUEST_SCREEN_CAPTURE = 1001
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Wire up native services so Flutter can access them
        ToolExecutor.registerWith(
            flutterEngine.dartExecutor.binaryMessenger,
            applicationContext
        )

        ScreenCaptureHelper.registerWith(
            flutterEngine.dartExecutor.binaryMessenger,
            this
        )
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)

        // Check if launched from AssistantActivity
        val screenshot = intent.getByteArrayExtra(AssistantActivity.EXTRA_SCREENSHOT)
        val screenText = intent.getStringExtra(AssistantActivity.EXTRA_SCREEN_TEXT)
        val timestamp = intent.getLongExtra(AssistantActivity.EXTRA_TIMESTAMP, 0L)

        if (screenshot != null) {
            AssistantActivity.latestScreenshot = screenshot
            AssistantActivity.latestScreenText = screenText
            AssistantActivity.latestTimestamp = timestamp
            android.util.Log.d("NovaMain", "Received screenshot from assistant: ${screenshot.size} bytes")
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_SCREEN_CAPTURE && resultCode == Activity.RESULT_OK && data != null) {
            ScreenCaptureHelper.startCapture(this, data)
        }
    }
}