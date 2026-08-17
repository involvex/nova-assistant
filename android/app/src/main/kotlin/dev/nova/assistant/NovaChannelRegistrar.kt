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

/**
 * Centralises all MethodChannel / EventChannel registrations so both
 * [MainActivity] and [OverlayActivity] share the same native bindings.
 */
object NovaChannelRegistrar {
    private const val TAG = "NovaChannelRegistrar"

    // ── Share helpers (moved from MainActivity) ──────────────────────────
    private const val SHARE_PREFS_NAME = "NovaSharePreferences"
    private const val PENDING_SHARE_KEY = "nova_pending_share"

    @Volatile
    private var pendingShareText: String? = null

    private var shareEventSink: EventChannel.EventSink? = null
    private var assistantRoleEventSink: EventChannel.EventSink? = null

    /**
     * Registers every platform channel that the app needs.
     * Call once per configured [FlutterEngine], passing the hosting activity.
     */
    fun registerWith(flutterEngine: FlutterEngine, activity: FlutterActivity) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val appContext = activity.applicationContext

        // ── Tool executor ──────────────────────────────────────────────
        ToolExecutor.registerWith(messenger, appContext)

        // ── Shizuku ────────────────────────────────────────────────────
        MethodChannel(messenger, "dev.nova.assistant/shizuku")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "status" -> result.success(ShizukuPowerHelper.status())
                        "requestPermission" ->
                            result.success(ShizukuPowerHelper.requestPermission(activity))
                        "forceStop" -> {
                            val pkg = call.argument<String>("package")
                                ?: throw IllegalArgumentException("package required")
                            result.success(ShizukuPowerHelper.forceStopPackage(pkg))
                        }
                        "openAppInfo" -> {
                            val pkg = call.argument<String>("package")
                                ?: throw IllegalArgumentException("package required")
                            result.success(
                                ShizukuPowerHelper.openAppInfo(appContext, pkg),
                            )
                        }
                        "openBatterySettings" ->
                            result.success(
                                ShizukuPowerHelper.openBatterySettings(appContext),
                            )
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("SHIZUKU_ERROR", e.message, null)
                }
            }

        // ── Screen capture ─────────────────────────────────────────────
        ScreenCaptureHelper.registerWith(messenger, activity)

        // ── Share (method + event) ─────────────────────────────────────
        MethodChannel(messenger, "dev.nova.assistant/share")
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
                        activity.startActivity(Intent.createChooser(intent, subject))
                        result.success(true)
                    }
                    "getPendingShare" -> {
                        val pending = consumePendingShare(activity)
                        result.success(pending)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(messenger, "dev.nova.assistant/share_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    shareEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    shareEventSink = null
                }
            })

        // ── Diagnostics ────────────────────────────────────────────────
        MethodChannel(messenger, "dev.nova.assistant/diagnostics")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getProcessMemory" -> {
                        val activityManager =
                            appContext.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
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

        // ── Main (assistant-role helpers) ───────────────────────────────
        MethodChannel(messenger, "dev.nova.assistant/main")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestAssistantRole" -> {
                        requestAssistantRole(activity)
                        result.success(true)
                    }
                    "isAssistantRoleHeld" -> {
                        result.success(isAssistantRoleHeld(activity))
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Battery ────────────────────────────────────────────────────
        MethodChannel(messenger, "dev.nova.assistant/battery")
            .setMethodCallHandler { call, result ->
                if (call.method == "getBatteryLevel") {
                    result.success(getBatteryLevel(appContext))
                } else {
                    result.notImplemented()
                }
            }

        // ── Model service ──────────────────────────────────────────────
        MethodChannel(messenger, "dev.nova.assistant/model_service")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val modelName = call.argument<String>("modelName") ?: "Nova"
                        startModelService(appContext, modelName)
                        result.success(true)
                    }
                    "stop" -> {
                        stopModelService(appContext)
                        result.success(true)
                    }
                    "isRunning" -> {
                        result.success(ModelService.isRunning)
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        result.success(isIgnoringBatteryOptimizations(appContext))
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Image generation ────────────────────────────────────────────
        ImageGenerationService.registerWith(messenger, appContext)

        // ── Main events ────────────────────────────────────────────────
        EventChannel(messenger, "dev.nova.assistant/main_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    assistantRoleEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    assistantRoleEventSink = null
                }
            })
    }

    // ── Pending-share helpers ────────────────────────────────────────────

    fun storePendingShare(context: Context, text: String) {
        pendingShareText = text
        context.getSharedPreferences(SHARE_PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(PENDING_SHARE_KEY, text)
            .apply()
    }

    fun clearPendingShare(context: Context) {
        pendingShareText = null
        context.getSharedPreferences(SHARE_PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(PENDING_SHARE_KEY)
            .apply()
    }

    fun consumePendingShare(context: Context): String? {
        val fromMemory = pendingShareText
        val fromPrefs = context.getSharedPreferences(SHARE_PREFS_NAME, Context.MODE_PRIVATE)
            .getString(PENDING_SHARE_KEY, null)
        clearPendingShare(context)
        return fromMemory?.takeIf { it.isNotBlank() }
            ?: fromPrefs?.takeIf { it.isNotBlank() }
    }

    /**
     * Called from both activities when they receive an ACTION_SEND intent.
     * Pushes the shared text to the Flutter event sink (if listening) or
     * stores it for the next cold start.
     */
    fun handleShareIntent(context: Context, intent: Intent) {
        val type = intent.type ?: ""
        if (!type.startsWith("text/")) {
            Log.d(TAG, "Ignoring non-text share type: $type")
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

        Log.d(TAG, "Share received (${combined.length} chars)")
        storePendingShare(context, combined)
        val sink = shareEventSink
        if (sink != null) {
            sink.success(combined)
            clearPendingShare(context)
        }
    }

    // ── Private helpers ──────────────────────────────────────────────────

    private fun isAssistantRoleHeld(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val roleManager = context.getSystemService(RoleManager::class.java)
                return roleManager?.isRoleHeld(RoleManager.ROLE_ASSISTANT) == true
            } catch (_: Exception) {}
        }
        return false
    }

    private fun requestAssistantRole(activity: Activity) {
        try {
            val intent = Intent(Settings.ACTION_VOICE_INPUT_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
        } catch (e: Exception) {
            try {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = android.net.Uri.parse("package:${activity.packageName}")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                activity.startActivity(intent)
            } catch (_: Exception) {}
        }
    }

    private fun getBatteryLevel(context: Context): Int {
        val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as android.os.BatteryManager
        return batteryManager.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY)
    }

    private fun startModelService(context: Context, modelName: String) {
        val intent = Intent(context, ModelService::class.java).apply {
            putExtra("modelName", modelName)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
        Log.d(TAG, "ModelService started for $modelName")
    }

    private fun stopModelService(context: Context) {
        val intent = Intent(context, ModelService::class.java)
        context.stopService(intent)
        Log.d(TAG, "ModelService stopped")
    }

    private fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
            return powerManager.isIgnoringBatteryOptimizations(context.packageName)
        }
        return true
    }
}
