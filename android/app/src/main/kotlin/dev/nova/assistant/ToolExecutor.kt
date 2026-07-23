package dev.nova.assistant

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.AlarmClock
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * ToolExecutor — executes function calls made by the Gemma model.
 * Called from Flutter via platform channel, runs in the native Android context.
 * Supports progress streaming via EventChannel for long-running tools.
 */
object ToolExecutor {

    private const val TAG = "NovaToolExecutor"
    private const val CHANNEL = "dev.nova.assistant/tools"
    private const val PROGRESS_CHANNEL = "dev.nova.assistant/tools_progress"

    private var progressEventSink: EventChannel.EventSink? = null

    fun registerWith(messenger: io.flutter.plugin.common.BinaryMessenger, context: Context) {
        EventChannel(messenger, PROGRESS_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                progressEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                progressEventSink = null
            }
        })

        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
            val toolName = call.method

            Log.d(TAG, "Executing tool: $toolName")

            try {
                val output = when (toolName) {
                    "get_time" -> getTime()
                    "set_alarm" -> setAlarm(context, args)
                    "cancel_alarm" -> cancelAlarm(context, args)
                    "open_app" -> openApp(context, args)
                    "search_web" -> searchWeb(context, args)
                    "get_weather" -> getWeather(args)
                    "send_sms" -> sendSms(context, args)
                    "open_settings" -> openSettings(context)
                    "take_screenshot" -> takeScreenshot()
                    "force_stop_app" -> {
                        val pkg = args["package"] as? String
                            ?: throw IllegalArgumentException("package required")
                        ShizukuPowerHelper.forceStopPackage(pkg)
                    }
                    "open_app_info" -> {
                        val pkg = args["package"] as? String
                            ?: throw IllegalArgumentException("package required")
                        ShizukuPowerHelper.openAppInfo(context, pkg)
                    }
                    "open_battery_settings" -> ShizukuPowerHelper.openBatterySettings(context)
                    else -> throw IllegalArgumentException("Unknown tool: $toolName")
                }
                result.success(output)
            } catch (e: Exception) {
                Log.e(TAG, "Tool execution failed: $toolName — ${e.message}")
                sendProgress(toolName, "error", null, e.message)
                result.error("TOOL_ERROR", e.message, null)
            }
        }
    }

    fun sendProgress(toolName: String, stage: String, percent: Double?, message: String?) {
        try {
            val event = hashMapOf<String, Any?>(
                "toolName" to toolName,
                "stage" to stage,
                "percent" to percent,
                "message" to message,
            )
            progressEventSink?.success(event)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send progress: ${e.message}")
        }
    }

    private fun getTime(): Map<String, Any> {
        val now = java.util.Calendar.getInstance()
        return mapOf(
            "time" to String.format("%02d:%02d", now.get(java.util.Calendar.HOUR_OF_DAY), now.get(java.util.Calendar.MINUTE)),
            "date" to String.format("%04d-%02d-%02d",
                now.get(java.util.Calendar.YEAR),
                now.get(java.util.Calendar.MONTH) + 1,
                now.get(java.util.Calendar.DAY_OF_MONTH)),
            "dayOfWeek" to listOf("Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday")
                [now.get(java.util.Calendar.DAY_OF_WEEK) - 1]
        )
    }

    private fun setAlarm(context: Context, args: Map<*, *>): Map<String, Any> {
        var hour = (args["hour"] as? Number)?.toInt()
        var minute = (args["minute"] as? Number)?.toInt()
        val durationMinutes = (args["duration_minutes"] as? Number)?.toInt()
            ?: (args["duration"] as? Number)?.toInt()
            ?: (args["minutes"] as? Number)?.toInt()

        if ((hour == null || minute == null) && durationMinutes != null && durationMinutes > 0) {
            val cal = java.util.Calendar.getInstance()
            cal.add(java.util.Calendar.MINUTE, durationMinutes)
            hour = cal.get(java.util.Calendar.HOUR_OF_DAY)
            minute = cal.get(java.util.Calendar.MINUTE)
        }

        hour ?: throw IllegalArgumentException("hour required")
        minute ?: throw IllegalArgumentException("minute required")

        val message = args["message"] as? String
            ?: if (durationMinutes != null && durationMinutes > 0) {
                "Timer $durationMinutes min"
            } else {
                "Alarm"
            }

        sendProgress("set_alarm", "executing", 0.5, "Setting alarm for $hour:$minute...")
        val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
            putExtra(AlarmClock.EXTRA_HOUR, hour)
            putExtra(AlarmClock.EXTRA_MINUTES, minute)
            putExtra(AlarmClock.EXTRA_MESSAGE, message)
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)

        sendProgress("set_alarm", "done", 1.0, null)
        return mapOf("success" to true, "alarmSet" to "$hour:$minute — $message")
    }

    private fun cancelAlarm(context: Context, args: Map<*, *>): Map<String, Any> {
        val hour = (args["hour"] as? Number)?.toInt()
            ?: throw IllegalArgumentException("hour required")
        val minute = (args["minute"] as? Number)?.toInt()
            ?: throw IllegalArgumentException("minute required")

        val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
            putExtra(AlarmClock.EXTRA_ALARM_SEARCH_MODE, AlarmClock.ALARM_SEARCH_MODE_TIME)
            putExtra(AlarmClock.EXTRA_HOUR, hour)
            putExtra(AlarmClock.EXTRA_MINUTES, minute)
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)

        return mapOf("success" to true)
    }

    private fun openApp(context: Context, args: Map<*, *>): Map<String, Any> {
        val packageName = args["package"] as? String
            ?: throw IllegalArgumentException("package name required")

        val pm = context.packageManager
        val launchIntent = resolveLaunchIntent(pm, packageName)
            ?: throw IllegalArgumentException(
                "App not found or not launchable: $packageName. " +
                    "If it is installed, disable \"Pause app if unused\" for it, " +
                    "or open it once from the launcher.",
            )

        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(launchIntent)

        return mapOf("success" to true, "opened" to packageName)
    }

    /** Prefer standard launcher intent; fall back to MAIN/LAUNCHER query. */
    private fun resolveLaunchIntent(
        pm: android.content.pm.PackageManager,
        packageName: String,
    ): Intent? {
        pm.getLaunchIntentForPackage(packageName)?.let { return it }

        val main = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
            setPackage(packageName)
        }
        val activities = pm.queryIntentActivities(main, 0)
        val first = activities.firstOrNull() ?: return null
        return Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
            setClassName(first.activityInfo.packageName, first.activityInfo.name)
        }
    }

    private fun searchWeb(context: Context, args: Map<*, *>): Map<String, Any> {
        val query = when (val raw = args["query"] ?: args["q"] ?: args["queries"]) {
            is String -> raw
            is List<*> -> raw.mapNotNull { it?.toString()?.trim() }
                .filter { it.isNotEmpty() }
                .joinToString(" ")
            else -> null
        } ?: throw IllegalArgumentException("query required")

        sendProgress("search_web", "executing", 0.3, "Opening browser for: $query")
        val intent = Intent(Intent.ACTION_WEB_SEARCH).apply {
            putExtra("query", query)
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)

        sendProgress("search_web", "done", 1.0, null)
        return mapOf("success" to true, "searched" to query)
    }

    private fun getWeather(args: Map<*, *>): Map<String, Any> {
        val location = args["location"] as? String ?: "current location"
        sendProgress("get_weather", "executing", 0.3, "Fetching weather for $location...")

        // Placeholder — in production, call a real weather API here.
        val result = mapOf(
            "location" to location,
            "temperature" to "22\u00B0C",
            "condition" to "Partly Cloudy",
            "note" to "Weather API not connected \u2014 set up OpenWeatherMap or similar"
        )

        sendProgress("get_weather", "done", 1.0, null)
        return result
    }

    private fun sendSms(context: Context, args: Map<*, *>): Map<String, Any> {
        val phoneNumber = args["phone"] as? String
            ?: throw IllegalArgumentException("phone number required")
        val message = args["message"] as? String ?: ""

        sendProgress("send_sms", "executing", 0.4, "Opening SMS for $phoneNumber...")
        val intent = Intent(Intent.ACTION_SENDTO).apply {
            data = Uri.parse("smsto:$phoneNumber")
            putExtra("sms_body", message)
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)

        sendProgress("send_sms", "done", 1.0, null)
        return mapOf("success" to true, "sentTo" to phoneNumber)
    }

    private fun openSettings(context: Context): Map<String, Any> {
        val intent = Intent(Settings.ACTION_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        return mapOf("success" to true)
    }

    private fun takeScreenshot(): Map<String, Any> {
        // Do NOT embed image bytes in this MethodChannel map — large ByteArray
        // payloads are unreliable here. Flutter fetches via ScreenshotService.
        val frame = AssistantActivity.latestScreenshot
            ?: ScreenCaptureHelper.latestFrame
        return buildMap {
            put("success", frame != null)
            put("hasScreenshot", frame != null)
            put("bytes", frame?.size ?: 0)
            if (frame == null) {
                put(
                    "error",
                    "No screenshot available. Use assistant mode or attach a screenshot first.",
                )
            }
        }
    }
}
