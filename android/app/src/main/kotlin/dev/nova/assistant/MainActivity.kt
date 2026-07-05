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
    }

    private var assistantRoleEventSink: EventChannel.EventSink? = null

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

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)

        val screenshotPath = intent.getStringExtra(AssistantActivity.EXTRA_SCREENSHOT_PATH)
        val screenText = intent.getStringExtra(AssistantActivity.EXTRA_SCREEN_TEXT)
        val timestamp = intent.getLongExtra(AssistantActivity.EXTRA_TIMESTAMP, 0L)

        if (screenshotPath != null) {
            val file = File(screenshotPath)
            if (file.exists()) {
                val bytes = file.readBytes()
                AssistantActivity.latestScreenshot = bytes
                AssistantActivity.latestScreenText = screenText
                AssistantActivity.latestTimestamp = timestamp
                Log.d("NovaMain", "Screenshot from assistant: ${bytes.size} bytes")
                file.delete()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQUEST_SCREEN_CAPTURE -> {
                val granted = resultCode == Activity.RESULT_OK && data != null
                if (granted && data != null) {
                    ScreenCaptureHelper.startCapture(this, data)
                    ScreenCaptureHelper.onScreenCapturePermissionResult(true)
                } else {
                    ScreenCaptureHelper.onScreenCapturePermissionResult(false)
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