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
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * ToolExecutor — executes function calls made by the Gemma model.
 * Called from Flutter via platform channel, runs in the native Android context.
 */
object ToolExecutor {

    private const val TAG = "NovaToolExecutor"
    private val CHANNEL = "dev.nova.assistant/tools"

    fun registerWith(messenger: io.flutter.plugin.common.BinaryMessenger, context: Context) {
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
                result.error("TOOL_ERROR", e.message, null)
            }
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

        val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
            putExtra(AlarmClock.EXTRA_HOUR, hour)
            putExtra(AlarmClock.EXTRA_MINUTES, minute)
            putExtra(AlarmClock.EXTRA_MESSAGE, message)
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)

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

        val intent = Intent(Intent.ACTION_WEB_SEARCH).apply {
            putExtra("query", query)
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)

        return mapOf("success" to true, "searched" to query)
    }

    private fun getWeather(args: Map<*, *>): Map<String, Any> {
        val location = args["location"] as? String ?: "current location"
        // In a production app, you'd call a weather API here.
        // For now, return a placeholder.
        return mapOf(
            "location" to location,
            "temperature" to "22°C",
            "condition" to "Partly Cloudy",
            "note" to "Weather API not connected — set up OpenWeatherMap or similar"
        )
    }

    private fun sendSms(context: Context, args: Map<*, *>): Map<String, Any> {
        val phoneNumber = args["phone"] as? String
            ?: throw IllegalArgumentException("phone number required")
        val message = args["message"] as? String ?: ""

        val intent = Intent(Intent.ACTION_SENDTO).apply {
            data = Uri.parse("smsto:$phoneNumber")
            putExtra("sms_body", message)
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)

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