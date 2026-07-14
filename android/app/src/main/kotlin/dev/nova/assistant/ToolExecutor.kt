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
        val hour = args["hour"] as? Int ?: throw IllegalArgumentException("hour required")
        val minute = args["minute"] as? Int ?: throw IllegalArgumentException("minute required")
        val message = args["message"] as? String ?: "Alarm"

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
        val hour = args["hour"] as? Int ?: throw IllegalArgumentException("hour required")
        val minute = args["minute"] as? Int ?: throw IllegalArgumentException("minute required")

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

        val launchIntent = context.packageManager.getLaunchIntentForPackage(packageName)
            ?: throw IllegalArgumentException("App not found: $packageName")

        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(launchIntent)

        return mapOf("success" to true, "opened" to packageName)
    }

    private fun searchWeb(context: Context, args: Map<*, *>): Map<String, Any> {
        val query = args["query"] as? String
            ?: throw IllegalArgumentException("query required")

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
        val frame = AssistantActivity.latestScreenshot
        return buildMap {
            put("success", frame != null)
            put("hasScreenshot", frame != null)
            put("bytes", frame?.size ?: 0)
            if (frame != null) {
                put("data", frame)
            }
        }
    }
}
