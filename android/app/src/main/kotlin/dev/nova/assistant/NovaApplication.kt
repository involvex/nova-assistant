package dev.nova.assistant

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.util.Log
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.lang.ref.WeakReference

/**
 * Scrubs oversized chat-history keys from Flutter SharedPreferences **without**
 * calling [getSharedPreferences]. Loading a 100MB+ prefs XML OOMs during
 * KXmlParser (POCO F1 / mid-RAM devices).
 *
 * Also tracks the live Flutter [Activity] so assistant launches can reuse a
 * single engine instead of stacking OverlayActivity + MainActivity.
 */
class NovaApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        instance = this
        scrubOversizedFlutterPrefs()
        registerActivityLifecycleCallbacks(FlutterActivityTracker)
    }

    private fun scrubOversizedFlutterPrefs() {
        val prefsFile = File(dataDir, "shared_prefs/$FLUTTER_PREFS.xml")
        val size = if (prefsFile.exists()) prefsFile.length() else 0L
        // #region agent log
        Log.i(
            TAG,
            "AGENT_DBG session=7abc09 hyp=A scrub start size=$size path=${prefsFile.absolutePath}",
        )
        // #endregion
        if (!prefsFile.exists() || size == 0L) return

        try {
            var removed = false
            for (key in listOf(CONVERSATIONS_KEY, OLD_CHAT_KEY)) {
                if (streamRemoveStringEntry(prefsFile, key)) {
                    removed = true
                    // #region agent log
                    Log.i(TAG, "AGENT_DBG session=7abc09 hyp=A removed key=$key")
                    // #endregion
                }
            }

            val after = prefsFile.length()
            // #region agent log
            Log.i(
                TAG,
                "AGENT_DBG session=7abc09 hyp=A scrub done removed=$removed sizeAfter=$after",
            )
            // #endregion

            if (after > MAX_SAFE_PREFS_BYTES) {
                // Do not copyTo() a huge file (that also OOMs). Just replace.
                prefsFile.delete()
                prefsFile.writeText(EMPTY_PREFS_XML)
                // #region agent log
                Log.w(
                    TAG,
                    "AGENT_DBG session=7abc09 hyp=A wiped prefs after=$after",
                )
                // #endregion
            }
        } catch (e: Exception) {
            Log.e(TAG, "AGENT_DBG session=7abc09 hyp=A scrub failed", e)
            try {
                prefsFile.writeText(EMPTY_PREFS_XML)
            } catch (_: Exception) {
                // User must clear app data.
            }
        }
    }

    /**
     * Removes `<string name="KEY">…</string>` via streaming so the huge value
     * is never materialized as a Java String.
     */
    private fun streamRemoveStringEntry(prefsFile: File, key: String): Boolean {
        val open = """<string name="$key">""".toByteArray(Charsets.UTF_8)
        val close = "</string>".toByteArray(Charsets.UTF_8)
        val tmp = File(prefsFile.parent, "${prefsFile.name}.tmp")
        var found = false

        FileInputStream(prefsFile).use { fis ->
            BufferedInputStream(fis, 256 * 1024).use { input ->
                FileOutputStream(tmp).use { fos ->
                    BufferedOutputStream(fos, 256 * 1024).use { output ->
                        val buffer = ByteArray(256 * 1024)
                        val pending = ArrayList<Byte>(open.size)
                        var openIdx = 0
                        var skipping = false
                        var closeIdx = 0

                        while (true) {
                            val n = input.read(buffer)
                            if (n < 0) break
                            var i = 0
                            while (i < n) {
                                val byte = buffer[i]

                                if (skipping) {
                                    if (byte == close[closeIdx]) {
                                        closeIdx++
                                        if (closeIdx == close.size) {
                                            skipping = false
                                            closeIdx = 0
                                            found = true
                                        }
                                    } else {
                                        closeIdx = if (byte == close[0]) 1 else 0
                                    }
                                    i++
                                    continue
                                }

                                if (byte == open[openIdx]) {
                                    pending.add(byte)
                                    openIdx++
                                    if (openIdx == open.size) {
                                        skipping = true
                                        openIdx = 0
                                        pending.clear()
                                    }
                                    i++
                                    continue
                                }

                                if (openIdx > 0) {
                                    for (p in pending) {
                                        output.write(p.toInt())
                                    }
                                    pending.clear()
                                    openIdx = 0
                                    continue
                                }

                                output.write(byte.toInt())
                                i++
                            }
                        }

                        if (!skipping) {
                            for (p in pending) {
                                output.write(p.toInt())
                            }
                        }
                    }
                }
            }
        }

        if (found) {
            if (!tmp.renameTo(prefsFile)) {
                tmp.copyTo(prefsFile, overwrite = true)
                tmp.delete()
            }
        } else {
            tmp.delete()
        }

        return found
    }

    companion object {
        private const val TAG = "NovaApplication"
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val CONVERSATIONS_KEY = "flutter.conversations"
        private const val OLD_CHAT_KEY = "flutter.chat_history"
        private const val MAX_SAFE_PREFS_BYTES = 4L * 1024L * 1024L
        private const val EMPTY_PREFS_XML =
            "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n" +
                "<map>\n</map>\n"

        @Volatile
        var instance: NovaApplication? = null
            private set

        /** True when [MainActivity] is created and not destroyed. */
        fun isMainFlutterAlive(): Boolean = FlutterActivityTracker.mainAlive

        /** True when [OverlayActivity] is created and not destroyed. */
        fun isOverlayFlutterAlive(): Boolean = FlutterActivityTracker.overlayAlive
    }
}

/**
 * Tracks whether a Flutter UI activity is already resident so assistant
 * launches can avoid spawning a second Dart isolate / Gemma load.
 */
object FlutterActivityTracker : Application.ActivityLifecycleCallbacks {
    private const val TAG = "FlutterActivityTracker"

    @Volatile
    var mainAlive: Boolean = false
        private set

    @Volatile
    var overlayAlive: Boolean = false
        private set

    private var mainRef: WeakReference<Activity>? = null
    private var overlayRef: WeakReference<Activity>? = null

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
        when (activity) {
            is MainActivity -> {
                mainAlive = true
                mainRef = WeakReference(activity)
                Log.i(TAG, "MainActivity created (overlayAlive=$overlayAlive)")
            }
            is OverlayActivity -> {
                overlayAlive = true
                overlayRef = WeakReference(activity)
                Log.i(TAG, "OverlayActivity created (mainAlive=$mainAlive)")
            }
        }
    }

    override fun onActivityDestroyed(activity: Activity) {
        when (activity) {
            is MainActivity -> {
                if (mainRef?.get() === activity) {
                    mainAlive = false
                    mainRef = null
                    Log.i(TAG, "MainActivity destroyed")
                }
            }
            is OverlayActivity -> {
                if (overlayRef?.get() === activity) {
                    overlayAlive = false
                    overlayRef = null
                    Log.i(TAG, "OverlayActivity destroyed")
                }
            }
        }
    }

    /** Finish a live Overlay so Main can own the only Flutter engine. */
    fun finishOverlayIfAlive() {
        val overlay = overlayRef?.get()
        if (overlay != null && !overlay.isFinishing) {
            Log.i(TAG, "Finishing OverlayActivity to keep a single Flutter engine")
            overlay.finish()
        }
    }

    /** Finish a live Main when Overlay must take over (rare). */
    fun finishMainIfAlive() {
        val main = mainRef?.get()
        if (main != null && !main.isFinishing) {
            Log.i(TAG, "Finishing MainActivity to keep a single Flutter engine")
            main.finish()
        }
    }

    override fun onActivityStarted(activity: Activity) {}
    override fun onActivityResumed(activity: Activity) {}
    override fun onActivityPaused(activity: Activity) {}
    override fun onActivityStopped(activity: Activity) {}
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
}
