package dev.nova.assistant

import android.app.Activity
import android.app.ActivityManager
import android.app.role.RoleManager
import android.content.Context
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
 * Also handles launching from the assistant button via Intent extras
 * and receiving shared text/URLs via ACTION_SEND.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val REQUEST_SCREEN_CAPTURE = 1001
        private const val REQUEST_ASSISTANT_ROLE = 1002
        private const val METHOD_CHANNEL = "dev.nova.assistant/main"
        private const val DIAGNOSTICS_CHANNEL = "dev.nova.assistant/diagnostics"
        private const val EVENT_CHANNEL = "dev.nova.assistant/main_events"
        private const val SHARE_METHOD_CHANNEL = "dev.nova.assistant/share"
        private const val SHARE_EVENT_CHANNEL = "dev.nova.assistant/share_events"
        private const val WIDGET_ACTION_KEY = "home_widget_action"
        private const val SHARE_PREFS_NAME = "NovaSharePreferences"
        private const val PENDING_SHARE_KEY = "nova_pending_share"
        const val WIDGET_PREFS_NAME = "HomeWidgetPreferences"

        @Volatile
        private var pendingShareText: String? = null
    }

    private var assistantRoleEventSink: EventChannel.EventSink? = null
    private var shareEventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        ToolExecutor.registerWith(
            flutterEngine.dartExecutor.binaryMessenger,
            applicationContext
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.nova.assistant/shizuku")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "status" -> result.success(ShizukuPowerHelper.status())
                        "requestPermission" ->
                            result.success(ShizukuPowerHelper.requestPermission(this))
                        "forceStop" -> {
                            val pkg = call.argument<String>("package")
                                ?: throw IllegalArgumentException("package required")
                            result.success(ShizukuPowerHelper.forceStopPackage(pkg))
                        }
                        "openAppInfo" -> {
                            val pkg = call.argument<String>("package")
                                ?: throw IllegalArgumentException("package required")
                            result.success(
                                ShizukuPowerHelper.openAppInfo(applicationContext, pkg),
                            )
                        }
                        "openBatterySettings" ->
                            result.success(
                                ShizukuPowerHelper.openBatterySettings(applicationContext),
                            )
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("SHIZUKU_ERROR", e.message, null)
                }
            }

        ScreenCaptureHelper.registerWith(
            flutterEngine.dartExecutor.binaryMessenger,
            this
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_METHOD_CHANNEL)
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
                    "getPendingShare" -> {
                        val pending = consumePendingShare()
                        result.success(pending)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    shareEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    shareEventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DIAGNOSTICS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getProcessMemory" -> {
                        val activityManager =
                            getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        val info = ActivityManager.MemoryInfo()
                        activityManager.getMemoryInfo(info)
                        val pid = android.os.Process.myPid()
                        val pids = intArrayOf(pid)
                        val memInfo = activityManager.getProcessMemoryInfo(pids)
                        val proc = memInfo.firstOrNull()
                        val pssKb = proc?.totalPss ?: 0
                        result.success(
                            mapOf(
                                "pssKb" to pssKb,
                                "rssKb" to pssKb,
                                "availMemMb" to (info.availMem / (1024 * 1024)),
                                "totalMemMb" to (info.totalMem / (1024 * 1024)),
                            )
                        )
                    }
                    "requestGc" -> {
                        System.gc()
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

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return

        if (intent.action == Intent.ACTION_SEND) {
            handleShareIntent(intent)
            return
        }

        val dataString = intent.dataString ?: return
        if (dataString.startsWith("nova://widget/")) {
            val action = dataString.removePrefix("nova://widget/")
            // Guard against system broadcasts that set their own action field
            if (action.startsWith("android.")) return
            Log.d("NovaMain", "Widget action received: $action")
            val prefs = getSharedPreferences(WIDGET_PREFS_NAME, 0)
            prefs.edit().putString(WIDGET_ACTION_KEY, action).apply()
        }
    }

    private fun handleShareIntent(intent: Intent) {
        val type = intent.type ?: ""
        if (!type.startsWith("text/")) {
            Log.d("NovaMain", "Ignoring non-text share type: $type")
            return
        }

        val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim().orEmpty()
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)?.trim().orEmpty()
        val combined = when {
            text.isEmpty() && subject.isEmpty() -> return
            text.isEmpty() -> subject
            subject.isEmpty() || text.contains(subject) -> text
            else -> "$subject\n$text"
        }

        if (combined.isBlank()) return

        Log.d("NovaMain", "Share received (${combined.length} chars)")
        storePendingShare(combined)
        val sink = shareEventSink
        if (sink != null) {
            sink.success(combined)
            // Delivered live — clear so a later cold start does not re-apply.
            clearPendingShare()
        }
    }

    private fun storePendingShare(text: String) {
        pendingShareText = text
        getSharedPreferences(SHARE_PREFS_NAME, MODE_PRIVATE)
            .edit()
            .putString(PENDING_SHARE_KEY, text)
            .apply()
    }

    private fun clearPendingShare() {
        pendingShareText = null
        getSharedPreferences(SHARE_PREFS_NAME, MODE_PRIVATE)
            .edit()
            .remove(PENDING_SHARE_KEY)
            .apply()
    }

    private fun consumePendingShare(): String? {
        val fromMemory = pendingShareText
        val prefs = getSharedPreferences(SHARE_PREFS_NAME, MODE_PRIVATE)
        val fromPrefs = prefs.getString(PENDING_SHARE_KEY, null)
        clearPendingShare()
        val result = fromMemory?.takeIf { it.isNotBlank() }
            ?: fromPrefs?.takeIf { it.isNotBlank() }
        return result
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
            REQUEST_SCREEN_CAPTURE,
            ScreenCaptureHelper.REQUEST_SCREEN_CAPTURE -> {
                val granted = resultCode == Activity.RESULT_OK && data != null
                if (granted && data != null) {
                    Log.d("NovaMain", "Screen capture permission granted")
                    ScreenCaptureHelper.startCapture(this, data)
                    ScreenCaptureHelper.onScreenCapturePermissionResult(true)
                } else {
                    Log.d("NovaMain", "Screen capture permission denied")
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
