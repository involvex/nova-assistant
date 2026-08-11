package dev.nova.assistant

import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * OverlayActivity — a lightweight translucent activity for quick assistant
 * responses.  Launched instead of [MainActivity] when the user presses the
 * system assistant button and the launch-mode preference is set to "overlay".
 *
 * Registers the same platform channels as [MainActivity] via
 * [NovaChannelRegistrar] and exposes an additional `dev.nova.assistant/overlay`
 * channel for UI visibility control.
 */
class OverlayActivity : FlutterActivity() {

    companion object {
        private const val TAG = "NovaOverlay"
        private const val OVERLAY_CHANNEL = "dev.nova.assistant/overlay"
    }

    private var originalWindowAlpha: Float = 1f

    /**
     * Renders the Flutter surface with alpha so the translucent window (and
     * the scrim drawn by the Dart side) actually shows the app underneath.
     * Without this the Flutter engine paints an opaque black backdrop.
     */
    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        NovaChannelRegistrar.registerWith(flutterEngine, this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OVERLAY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getLaunchMode" -> result.success("overlay")
                    "hideForCapture" -> {
                        originalWindowAlpha = window.decorView.alpha
                        window.decorView.alpha = 0f
                        Log.d(TAG, "Window hidden for capture (alpha=0)")
                        result.success(true)
                    }
                    "showAfterCapture" -> {
                        window.decorView.alpha = originalWindowAlpha
                        Log.d(TAG, "Window restored after capture (alpha=$originalWindowAlpha)")
                        result.success(true)
                    }
                    "expandToFullApp" -> {
                        Log.d(TAG, "Expanding to full app (MainActivity)")
                        val intent = Intent(this, MainActivity::class.java).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        finish()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
        )
        loadScreenshotFromIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        loadScreenshotFromIntent(intent)
    }

    /**
     * Reads screenshot extras written by [AssistantActivity] and stores them
     * in the shared companion statics so the Dart side can access them.
     * The temp file is deleted after reading.
     */
    private fun loadScreenshotFromIntent(intent: Intent?) {
        if (intent == null) return
        try {
            val screenshotPath = intent.getStringExtra(AssistantActivity.EXTRA_SCREENSHOT_PATH)
            val screenText = intent.getStringExtra(AssistantActivity.EXTRA_SCREEN_TEXT)
            val timestamp = intent.getLongExtra(AssistantActivity.EXTRA_TIMESTAMP, 0L)

            Log.d(TAG, "loadScreenshotFromIntent: path=$screenshotPath, text=$screenText, ts=$timestamp")

            if (screenshotPath != null) {
                AssistantActivity.isSystemAssistantLaunch = true
                val file = File(screenshotPath)
                if (file.exists()) {
                    try {
                        val bytes = file.readBytes()
                        AssistantActivity.latestScreenshot = bytes
                        AssistantActivity.latestScreenText = screenText
                        AssistantActivity.latestTimestamp = timestamp
                        Log.d(TAG, "Screenshot loaded: ${bytes.size} bytes")
                        file.delete()
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to read screenshot: ${e.message}")
                    }
                } else {
                    Log.w(TAG, "Screenshot file missing: $screenshotPath")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error loading screenshot: ${e.message}")
        }
    }
}
