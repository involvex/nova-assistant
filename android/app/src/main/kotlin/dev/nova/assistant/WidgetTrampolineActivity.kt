package dev.nova.assistant

import android.content.Intent
import android.os.Bundle
import android.util.Log

/**
 * Trampoline activity for widget button taps.
 * Launches instantly (singleTop, no animation) to handle the tap,
 * saves the action to the same SharedPreferences that home_widget uses,
 * and immediately launches MainActivity.
 *
 * Avoids Android 12+ background activity launch restrictions that apply
 * when a PendingIntent directly launches the main activity from background.
 */
class WidgetTrampolineActivity : androidx.appcompat.app.AppCompatActivity() {

    companion object {
        private const val WIDGET_ACTION_KEY = "home_widget_action"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val action = intent.action ?: run {
            finish()
            return
        }

        Log.d("NovaTrampoline", "Widget tap: $action")

        // Write to the same SharedPreferences file that home_widget uses.
        // HomeWidgetPlugin.kt line 270: PREFERENCES = "HomeWidgetPreferences"
        val prefs = getSharedPreferences("HomeWidgetPreferences", MODE_PRIVATE)
        prefs.edit().putString(WIDGET_ACTION_KEY, action).apply()

        val targetIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        startActivity(targetIntent)

        finish()
    }
}