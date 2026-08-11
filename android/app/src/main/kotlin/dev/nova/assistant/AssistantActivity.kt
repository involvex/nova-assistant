package dev.nova.assistant

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import java.io.File
import java.io.FileOutputStream

/**
 * AssistantActivity — Nova's entry point when the user triggers the system
 * assistant button (long-press home/gesture or power button).
 *
 * This is a lightweight transparent Activity — NOT a FlutterActivity.
 * It shows no Flutter UI so the screenshot captures the previous app,
 * not Nova's own chat UI. After capturing, it launches either
 * [OverlayActivity] or [MainActivity] depending on the user's
 * `assistant_launch_mode` preference.
 *
 * Screenshot is written to a temp file to avoid Binder transaction size limits.
 */
class AssistantActivity : Activity() {
    private val TAG = "NovaAssistant"

    companion object {
        const val EXTRA_SCREENSHOT_PATH = "nova_screenshot_path"
        const val EXTRA_SCREEN_TEXT = "nova_screen_text"
        const val EXTRA_TIMESTAMP = "nova_timestamp"
        private const val REQUEST_SCREEN_CAPTURE = 1001
        private const val LAUNCH_MODE_PREFS = "FlutterSharedPreferences"
        private const val LAUNCH_MODE_KEY = "flutter.assistant_launch_mode"
        private const val DEFAULT_LAUNCH_MODE = "overlay"

        var latestScreenshot: ByteArray? = null
        var latestScreenText: String? = null
        var latestTimestamp: Long = 0L

        /** Set to true when a Flutter activity starts with a screenshot from a system assistant trigger. */
        var isSystemAssistantLaunch: Boolean = false
    }

    private var launchScheduled = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "AssistantActivity: received ASSIST intent")
        requestScreenCaptureOrSkip()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d(TAG, "AssistantActivity: received ASSIST intent in onNewIntent")
        launchScheduled = false
        requestScreenCaptureOrSkip()
    }

    /**
     * If a MediaProjection is already active we can grab a fresh frame without
     * the system consent dialog.  Otherwise fall through to the normal
     * requestScreenCapture flow.
     */
    private fun requestScreenCaptureOrSkip() {
        // The process can stay alive between assistant invocations
        // (ModelService), so frames cached by a previous session must be
        // discarded or they would be passed to the UI as "current".
        latestScreenshot = null
        latestScreenText = null
        latestTimestamp = 0L
        ScreenCaptureHelper.clearStaleFrame()

        if (ScreenCaptureHelper.hasActiveProjection) {
            Log.d(TAG, "Projection already active — capturing fresh frame without consent")
            ScreenCaptureHelper.captureFreshFrame { launchMainApp() }
            return
        }
        requestScreenCapture()
    }

    private fun requestScreenCapture() {
        try {
            val mediaProjectionManager =
                getSystemService(MEDIA_PROJECTION_SERVICE) as android.media.projection.MediaProjectionManager
            startActivityForResult(
                mediaProjectionManager.createScreenCaptureIntent(),
                REQUEST_SCREEN_CAPTURE,
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to request screen capture: ${e.message}")
            launchMainApp()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_SCREEN_CAPTURE) return

        if (resultCode == Activity.RESULT_OK && data != null) {
            Log.d(TAG, "Screen capture permission granted")
            try {
                ScreenCaptureHelper.startCapture(this, data)
                ScreenCaptureHelper.waitForFirstFrame(timeoutMs = 2500L) {
                    launchMainApp()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start capture: ${e.message}")
                launchMainApp()
            }
        } else {
            Log.d(TAG, "Screen capture denied — launching without screenshot")
            launchMainApp()
        }
    }

    private fun launchMainApp() {
        if (launchScheduled) return
        launchScheduled = true

        val launchMode = getLaunchMode()
        Log.d(TAG, "Launch mode: $launchMode")

        val targetClass = if (launchMode == "overlay") {
            OverlayActivity::class.java
        } else {
            MainActivity::class.java
        }

        try {
            val screenshotPath = writeScreenshotToFile()

            val intent = Intent(this, targetClass).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                putExtra(EXTRA_SCREENSHOT_PATH, screenshotPath)
                putExtra(EXTRA_SCREEN_TEXT, latestScreenText)
                putExtra(EXTRA_TIMESTAMP, latestTimestamp)
            }
            Log.d(TAG, "Launching ${targetClass.simpleName} with screenshot: $screenshotPath")
            startActivity(intent)
            finish()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch main app: ${e.message}")
            try {
                // Fallback: try the other activity class
                val fallbackClass = if (targetClass == OverlayActivity::class.java) {
                    MainActivity::class.java
                } else {
                    OverlayActivity::class.java
                }
                val intent = Intent(this, fallbackClass).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
                startActivity(intent)
                finish()
            } catch (e2: Exception) {
                Log.e(TAG, "Failed to launch main app at all: ${e2.message}")
            }
        }
    }

    private fun getLaunchMode(): String {
        return try {
            getSharedPreferences(LAUNCH_MODE_PREFS, Context.MODE_PRIVATE)
                .getString(LAUNCH_MODE_KEY, DEFAULT_LAUNCH_MODE)
                ?: DEFAULT_LAUNCH_MODE
        } catch (e: Exception) {
            Log.w(TAG, "Failed to read launch mode pref: ${e.message}")
            DEFAULT_LAUNCH_MODE
        }
    }

    private fun writeScreenshotToFile(): String? {
        val data = latestScreenshot ?: ScreenCaptureHelper.latestFrame ?: return null
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
