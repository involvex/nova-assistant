package dev.nova.assistant

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * AssistantActivity — Nova's entry point when the user triggers the system
 * assistant button (long-press home/gesture or power button).
 *
 * Receives the ASSIST intent, captures the current screen, and passes
 * the screenshot + text to the main Flutter app for inference.
 */
class AssistantActivity : FlutterActivity() {
    private val TAG = "NovaAssistant"

    companion object {
        const val EXTRA_SCREENSHOT = "nova_screenshot"
        const val EXTRA_SCREEN_TEXT = "nova_screen_text"
        const val EXTRA_TIMESTAMP = "nova_timestamp"
        private const val REQUEST_SCREEN_CAPTURE = 1001

        var latestScreenshot: ByteArray? = null
        var latestScreenText: String? = null
        var latestTimestamp: Long = 0L
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "AssistantActivity: received ASSIST intent")

        // Immediately trigger screen capture
        requestScreenCapture()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Register method channel for screenshot retrieval from Flutter side
        dev.nova.assistant.ScreenCaptureHelper.registerWith(flutterEngine.dartExecutor.binaryMessenger, this)
    }

    private fun requestScreenCapture() {
        val mediaProjectionManager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        startActivityForResult(
            mediaProjectionManager.createScreenCaptureIntent(),
            REQUEST_SCREEN_CAPTURE
        )
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_SCREEN_CAPTURE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                Log.d(TAG, "Screen capture permission granted")
                ScreenCaptureHelper.startCapture(this, data)

                // Give it a moment to capture the first frame, then launch Flutter
                android.os.Handler(mainLooper).postDelayed({
                    launchMainApp()
                }, 500)
            } else {
                Log.d(TAG, "Screen capture denied — launching without screenshot")
                launchMainApp()
            }
        }
    }

    private fun launchMainApp() {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(EXTRA_SCREENSHOT, latestScreenshot)
            putExtra(EXTRA_SCREEN_TEXT, latestScreenText)
            putExtra(EXTRA_TIMESTAMP, latestTimestamp)
        }
        startActivity(intent)
        finish()
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "AssistantActivity destroyed")
    }
}