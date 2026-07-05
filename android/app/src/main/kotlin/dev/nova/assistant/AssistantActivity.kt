package dev.nova.assistant

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import java.io.File
import java.io.FileOutputStream

/**
 * AssistantActivity — Nova's entry point when the user triggers the system
 * assistant button (long-press home/gesture or power button).
 *
 * Receives the ASSIST intent, captures the current screen, and passes
 * the screenshot + text to the main Flutter app for inference.
 *
 * Screenshot is written to a temp file to avoid Binder transaction size limits.
 */
class AssistantActivity : FlutterActivity() {
    private val TAG = "NovaAssistant"

    companion object {
        const val EXTRA_SCREENSHOT_PATH = "nova_screenshot_path"
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

        requestScreenCapture()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        dev.nova.assistant.ScreenCaptureHelper.registerWith(flutterEngine.dartExecutor.binaryMessenger, this)
    }

    private fun requestScreenCapture() {
        val mediaProjectionManager = getSystemService(MEDIA_PROJECTION_SERVICE) as android.media.projection.MediaProjectionManager
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
        // Write screenshot to temp file to avoid Binder transaction size limit (~1MB)
        val screenshotPath = writeScreenshotToFile()

        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            if (screenshotPath != null) {
                putExtra(EXTRA_SCREENSHOT_PATH, screenshotPath)
            }
            putExtra(EXTRA_SCREEN_TEXT, latestScreenText)
            putExtra(EXTRA_TIMESTAMP, latestTimestamp)
        }
        startActivity(intent)
        finish()
    }

    private fun writeScreenshotToFile(): String? {
        val data = latestScreenshot ?: return null
        return try {
            val tempFile = File(cacheDir, "nova_screenshot_${System.currentTimeMillis()}.png")
            FileOutputStream(tempFile).use { it.write(data) }
            Log.d(TAG, "Screenshot written to file: ${tempFile.absolutePath} (${data.size} bytes)")
            tempFile.absolutePath
        } catch (e: Exception) {
            Log.e(TAG, "Failed to write screenshot to file: ${e.message}")
            null
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "AssistantActivity destroyed")
    }
}
