package dev.nova.assistant

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import rikka.shizuku.Shizuku
import java.io.BufferedReader
import java.io.InputStreamReader

/**
 * Optional power-user helpers via Shizuku (preferred) or su (rooted devices).
 * Does not write thermal/CPU governors.
 */
object ShizukuPowerHelper {
    private const val TAG = "NovaShizuku"
    private const val REQUEST_CODE = 0x4E56 // 'NV'

    @Volatile
    private var permissionListener: Shizuku.OnRequestPermissionResultListener? = null

    fun status(): Map<String, Any> {
        val binderAlive = try {
            Shizuku.pingBinder()
        } catch (_: Throwable) {
            false
        }
        val permission = try {
            if (!binderAlive) {
                false
            } else {
                Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
            }
        } catch (_: Throwable) {
            false
        }
        val shizukuVersion = try {
            if (binderAlive) Shizuku.getVersion() else -1
        } catch (_: Throwable) {
            -1
        }
        val suAvailable = isSuAvailable()

        return mapOf(
            "shizukuInstalled" to isShizukuInstalled(),
            "binderAlive" to binderAlive,
            "permissionGranted" to permission,
            "shizukuVersion" to shizukuVersion,
            "suAvailable" to suAvailable,
            "ready" to ((binderAlive && permission) || suAvailable),
        )
    }

    fun requestPermission(activity: Activity): Map<String, Any> {
        return try {
            if (!Shizuku.pingBinder()) {
                return mapOf(
                    "success" to false,
                    "error" to "Shizuku is not running. Open Shizuku and start the service.",
                )
            }
            if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) {
                return mapOf("success" to true, "alreadyGranted" to true)
            }
            ensurePermissionListener()
            Shizuku.requestPermission(REQUEST_CODE)
            mapOf("success" to true, "requested" to true)
        } catch (e: Throwable) {
            Log.e(TAG, "requestPermission failed", e)
            mapOf("success" to false, "error" to (e.message ?: "request failed"))
        }
    }

    fun forceStopPackage(packageName: String): Map<String, Any> {
        val pkg = packageName.trim()
        if (pkg.isEmpty() || !pkg.contains('.')) {
            return mapOf("success" to false, "error" to "Invalid package name")
        }
        if (pkg == "dev.nova.assistant") {
            return mapOf("success" to false, "error" to "Refusing to force-stop Nova itself")
        }

        val viaShizuku = tryForceStopShizuku(pkg)
        if (viaShizuku["success"] == true) return viaShizuku

        val viaSu = tryForceStopSu(pkg)
        if (viaSu["success"] == true) return viaSu

        val shizukuError = viaShizuku["error"] as? String
        val suError = viaSu["error"] as? String
        return mapOf(
            "success" to false,
            "error" to listOfNotNull(shizukuError, suError).joinToString(" | ")
                .ifEmpty { "Force-stop unavailable. Install/start Shizuku or use root." },
        )
    }

    fun openAppInfo(context: Context, packageName: String): Map<String, Any> {
        val pkg = packageName.trim()
        if (pkg.isEmpty()) {
            return mapOf("success" to false, "error" to "package required")
        }
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", pkg, null)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        return mapOf("success" to true, "opened" to "app_info", "package" to pkg)
    }

    fun openBatterySettings(context: Context): Map<String, Any> {
        val intent = Intent(Intent.ACTION_POWER_USAGE_SUMMARY).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            context.startActivity(intent)
            mapOf("success" to true, "opened" to "battery")
        } catch (_: Exception) {
            val fallback = Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            try {
                context.startActivity(fallback)
                mapOf("success" to true, "opened" to "battery_saver")
            } catch (e: Exception) {
                mapOf("success" to false, "error" to (e.message ?: "Cannot open battery settings"))
            }
        }
    }

    private fun ensurePermissionListener() {
        if (permissionListener != null) return
        val listener = Shizuku.OnRequestPermissionResultListener { requestCode, grantResult ->
            if (requestCode != REQUEST_CODE) return@OnRequestPermissionResultListener
            Log.d(TAG, "Shizuku permission result=$grantResult")
        }
        permissionListener = listener
        Shizuku.addRequestPermissionResultListener(listener)
    }

    private fun tryForceStopShizuku(packageName: String): Map<String, Any> {
        return try {
            if (!Shizuku.pingBinder()) {
                return mapOf("success" to false, "error" to "Shizuku binder not alive")
            }
            if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) {
                return mapOf("success" to false, "error" to "Shizuku permission not granted")
            }

            // Prefer shell via Shizuku.newProcess when available (API reflection).
            val process = newShizukuProcess(arrayOf("am", "force-stop", packageName))
                ?: return mapOf(
                    "success" to false,
                    "error" to "Shizuku shell API unavailable on this device",
                )
            val exit = process.waitFor()
            val err = process.errorStream.bufferedReader().use(BufferedReader::readText).trim()
            if (exit == 0) {
                mapOf("success" to true, "method" to "shizuku", "package" to packageName)
            } else {
                mapOf(
                    "success" to false,
                    "error" to "am force-stop exit=$exit${if (err.isNotEmpty()) ": $err" else ""}",
                )
            }
        } catch (e: Throwable) {
            Log.e(TAG, "Shizuku force-stop failed", e)
            mapOf("success" to false, "error" to (e.message ?: "Shizuku force-stop failed"))
        }
    }

    private fun newShizukuProcess(args: Array<String>): Process? {
        return try {
            val method = Shizuku::class.java.getDeclaredMethod(
                "newProcess",
                Array<String>::class.java,
                Array<String>::class.java,
                String::class.java,
            )
            method.isAccessible = true
            method.invoke(null, args, null, null) as Process
        } catch (e: Throwable) {
            Log.w(TAG, "Shizuku.newProcess unavailable: ${e.message}")
            null
        }
    }

    private fun tryForceStopSu(packageName: String): Map<String, Any> {
        return try {
            if (!isSuAvailable()) {
                return mapOf("success" to false, "error" to "su not available")
            }
            val process = Runtime.getRuntime().exec(arrayOf("su", "-c", "am force-stop $packageName"))
            val exit = process.waitFor()
            if (exit == 0) {
                mapOf("success" to true, "method" to "su", "package" to packageName)
            } else {
                mapOf("success" to false, "error" to "su am force-stop exit=$exit")
            }
        } catch (e: Throwable) {
            mapOf("success" to false, "error" to (e.message ?: "su force-stop failed"))
        }
    }

    private fun isSuAvailable(): Boolean {
        return try {
            val process = Runtime.getRuntime().exec(arrayOf("su", "-c", "id"))
            val exit = process.waitFor()
            exit == 0
        } catch (_: Throwable) {
            false
        }
    }

    private fun isShizukuInstalled(): Boolean {
        // Best-effort; package visibility may hide it without <queries>.
        return try {
            // Touch the API class — presence of binder is more reliable.
            Shizuku.getVersion()
            true
        } catch (_: Throwable) {
            Build.VERSION.SDK_INT >= 23
        }
    }
}
