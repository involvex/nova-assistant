package dev.nova.assistant

import android.app.Activity
import android.app.role.RoleManager
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * MainActivity — the primary Flutter activity for Nova.
 * Also handles launching from the assistant button via Intent extras.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val REQUEST_SCREEN_CAPTURE = 1001
        private const val REQUEST_ASSISTANT_ROLE = 1002
        private const val METHOD_CHANNEL = "dev.nova.assistant/main"
        private const val EVENT_CHANNEL = "dev.nova.assistant/main_events"
        private const val WIDGET_CHANNEL = "dev.nova.assistant/widget"
    }

    private var assistantRoleEventSink: EventChannel.EventSink? = null
    private var screenCapturePendingResult: MethodChannel.Result? = null
    private var pendingWidgetAction: String? = null
    private var widgetEventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        ToolExecutor.registerWith(
            flutterEngine.dartExecutor.binaryMessenger,
            applicationContext
        )

        ScreenCaptureHelper.registerWith(
            flutterEngine.dartExecutor.binaryMessenger,
            this
        )

        ScreenCaptureHelper.setPermissionResultCallback { granted ->
            runOnUiThread {
                screenCapturePendingResult?.success(granted)
                screenCapturePendingResult = null
                ScreenCaptureHelper.onScreenCapturePermissionResult(granted)
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.nova.assistant/share")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareText" -> {
                        val text = call.argument<String>("text") ?: ""
                        val subject = call.argument<String>("subject") ?: ""
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, text)
                            putExtra(Intent.EXTRA_SUBJECT, subject)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(Intent.createChooser(intent, subject))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestAssistantRole" -> {
                        requestAssistantRole()
                        result.success(true)
                    }
                    "isAssistantRoleHeld" -> {
                        result.success(isAssistantRoleHeld())
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    assistantRoleEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    assistantRoleEventSink = null
                }
            })

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    widgetEventSink = events
                    pendingWidgetAction?.let { action ->
                        runOnUiThread {
                            widgetEventSink?.success(action)
                            pendingWidgetAction = null
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    widgetEventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialWidgetAction" -> {
                        result.success(pendingWidgetAction)
                        pendingWidgetAction = null
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isAssistantRoleHeld(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val roleManager = getSystemService(RoleManager::class.java)
                return roleManager?.isRoleHeld(RoleManager.ROLE_ASSISTANT) == true
            } catch (_: Exception) {}
        }
        return false
    }

    private fun requestAssistantRole() {
        // Open voice input settings where user can select Nova as assistant.
        // On Android 14+, the ASSISTANT role is restricted to system apps,
        // so we rely on the ASSIST intent filter for assistant functionality.
        try {
            val intent = Intent(Settings.ACTION_VOICE_INPUT_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            try {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = android.net.Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
            } catch (_: Exception) {}
        }
    }

    private fun handleIntent(intent: Intent) {
        val dataString = intent.dataString ?: return
        if (dataString.startsWith("nova://widget/")) {
            val action = dataString.removePrefix("nova://widget/")
            Log.d("NovaMain", "Widget action received: $action")
            pendingWidgetAction = action
            widgetEventSink?.success(action)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)

        handleIntent(intent)

        try {
            val screenshotPath = intent.getStringExtra(AssistantActivity.EXTRA_SCREENSHOT_PATH)
            val screenText = intent.getStringExtra(AssistantActivity.EXTRA_SCREEN_TEXT)
            val timestamp = intent.getLongExtra(AssistantActivity.EXTRA_TIMESTAMP, 0L)

            Log.d("NovaMain", "onCreate: screenshotPath=$screenshotPath, screenText=$screenText, timestamp=$timestamp")

            if (screenshotPath != null) {
                val file = File(screenshotPath)
                if (file.exists()) {
                    try {
                        val bytes = file.readBytes()
                        AssistantActivity.latestScreenshot = bytes
                        AssistantActivity.latestScreenText = screenText
                        AssistantActivity.latestTimestamp = timestamp
                        Log.d("NovaMain", "Screenshot loaded from file: ${bytes.size} bytes")
                        file.delete()
                    } catch (e: Exception) {
                        Log.e("NovaMain", "Failed to read screenshot file: ${e.message}")
                    }
                } else {
                    Log.w("NovaMain", "Screenshot file does not exist: $screenshotPath")
                }
            } else {
                Log.d("NovaMain", "No screenshot path in intent")
            }
        } catch (e: Exception) {
            Log.e("NovaMain", "Error in onCreate: ${e.message}")
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQUEST_SCREEN_CAPTURE -> {
                val pendingResult = screenCapturePendingResult
                screenCapturePendingResult = null
                val granted = resultCode == Activity.RESULT_OK && data != null
                if (granted && data != null) {
                    ScreenCaptureHelper.startCapture(this, data)
                    pendingResult?.success(true)
                } else {
                    pendingResult?.success(false)
                }
            }
            REQUEST_ASSISTANT_ROLE -> {
                val held = isAssistantRoleHeld()
                Log.d("NovaMain", "Assistant role request done — held: $held")
                assistantRoleEventSink?.success(
                    mapOf("event" to "assistantRoleChanged", "held" to held)
                )
            }
        }
    }
}