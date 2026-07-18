package dev.nova.assistant

import android.app.Application
import android.util.Log
import java.io.File

/**
 * Migrates oversized chat history out of Flutter SharedPreferences before the
 * Dart engine starts. A ~100MB+ `flutter.conversations` value OOMs the
 * StandardMessageCodec when SharedPreferences.getInstance() loads all keys.
 */
class NovaApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        migrateConversationsOutOfPrefs()
    }

    private fun migrateConversationsOutOfPrefs() {
        try {
            val prefs = getSharedPreferences(FLUTTER_PREFS, MODE_PRIVATE)
            val value = prefs.getString(CONVERSATIONS_KEY, null)
            val oldValue = prefs.getString(OLD_CHAT_KEY, null)
            if (value == null && oldValue == null) return

            val outDir = File(dataDir, "app_flutter")
            if (!outDir.exists()) outDir.mkdirs()
            val outFile = File(outDir, CONVERSATIONS_FILE)

            if (value != null) {
                if (value.length > MAX_MIGRATE_CHARS) {
                    Log.w(
                        TAG,
                        "Dropping oversized $CONVERSATIONS_KEY " +
                            "(${value.length} chars) — would OOM Flutter prefs codec",
                    )
                } else if (!outFile.exists() || outFile.length() == 0L) {
                    outFile.writeText(value)
                    Log.i(
                        TAG,
                        "Migrated conversations prefs (${value.length} chars) → ${outFile.path}",
                    )
                }
                prefs.edit().remove(CONVERSATIONS_KEY).apply()
            }

            if (oldValue != null) {
                prefs.edit().remove(OLD_CHAT_KEY).apply()
            }
        } catch (e: Exception) {
            Log.e(TAG, "migrateConversationsOutOfPrefs failed", e)
            try {
                getSharedPreferences(FLUTTER_PREFS, MODE_PRIVATE)
                    .edit()
                    .remove(CONVERSATIONS_KEY)
                    .remove(OLD_CHAT_KEY)
                    .apply()
            } catch (_: Exception) {
                // Ignore — next launch may still crash until data is cleared.
            }
        }
    }

    companion object {
        private const val TAG = "NovaApplication"
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val CONVERSATIONS_KEY = "flutter.conversations"
        private const val OLD_CHAT_KEY = "flutter.chat_history"
        private const val CONVERSATIONS_FILE = "conversations.json"
        /** Above this, skip content migrate and only delete the prefs key. */
        private const val MAX_MIGRATE_CHARS = 8_000_000
    }
}
