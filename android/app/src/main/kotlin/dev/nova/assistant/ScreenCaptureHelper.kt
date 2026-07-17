package dev.nova.assistant

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Handles MediaProjection-based screen capture.
 * Uses RGBA_8888 with rowStride-aware decoding for reliable capture across GPUs.
 */
object ScreenCaptureHelper {
    private const val TAG = "NovaScreenCapture"
    private const val CHANNEL = "dev.nova.assistant/screenshot"
    const val REQUEST_SCREEN_CAPTURE = 1001

    private var mediaProjection: MediaProjection? = null
    private var imageReader: ImageReader? = null
    private var captureThread: HandlerThread? = null
    private var captureHandler: Handler? = null
    private var isCapturing = false
    private var captureWidth = 1080
    private var captureHeight = 2400

    private var _latestFrame: ByteArray? = null
    val latestFrame: ByteArray? get() = _latestFrame

    private var _captureCompletionCallback: ((Boolean) -> Unit)? = null
    private var _firstFrameCallback: (() -> Unit)? = null

    fun registerWith(messenger: BinaryMessenger, activity: Activity) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getLatestScreenshot" -> {
                    var frame = _latestFrame
                    if (frame == null) {
                        frame = AssistantActivity.latestScreenshot
                    }
                    if (frame != null) {
                        Log.d(TAG, "Returning screenshot: ${frame.size} bytes")
                        result.success(frame)
                    } else {
                        result.success(null)
                    }
                }
                "isCapturing" -> result.success(isCapturing)
                "requestCapture" -> {
                    if (mediaProjection != null) {
                        // Force a fresh frame even if one is already cached
                        captureHandler?.post {
                            captureFrame()
                            activity.runOnUiThread { result.success(true) }
                        } ?: run {
                            captureFrame()
                            result.success(true)
                        }
                    } else {
                        _captureCompletionCallback = { granted ->
                            if (granted) {
                                waitForFirstFrame(timeoutMs = 2000L) {
                                    activity.runOnUiThread { result.success(true) }
                                }
                            } else {
                                activity.runOnUiThread { result.success(false) }
                            }
                        }
                        requestScreenCapture(activity)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Starts capture after the user grants MediaProjection permission.
     * On API 34+, starts [MediaProjectionService] before creating the projection.
     */
    fun startCapture(context: Context, resultData: Intent) {
        if (isCapturing && mediaProjection != null) {
            captureHandler?.post { captureFrame() }
            return
        }

        resolveDisplaySize(context)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            MediaProjectionService.start(context)
            // Allow FGS to call startForeground before getMediaProjection (API 34+)
            Handler(Looper.getMainLooper()).postDelayed({
                beginProjection(context, resultData)
            }, 350)
        } else {
            beginProjection(context, resultData)
        }
    }

    private fun beginProjection(context: Context, resultData: Intent) {
        try {
            val projectionManager =
                context.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            mediaProjection = projectionManager.getMediaProjection(Activity.RESULT_OK, resultData)

            imageReader = ImageReader.newInstance(
                captureWidth,
                captureHeight,
                PixelFormat.RGBA_8888,
                2,
            )

            captureThread = HandlerThread("NovaScreenCapture").apply { start() }
            captureHandler = Handler(captureThread!!.looper)

            mediaProjection?.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    Log.d(TAG, "MediaProjection stopped")
                    releaseProjection(context)
                }
            }, captureHandler)

            mediaProjection?.createVirtualDisplay(
                "NovaScreenCapture",
                captureWidth,
                captureHeight,
                context.resources.displayMetrics.densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                imageReader!!.surface,
                null,
                captureHandler,
            )

            isCapturing = true

            // Capture only the first frame, then drain extras without re-encoding.
            // Continuous captureFrame() flooded the UI thread and BLAST buffer.
            imageReader?.setOnImageAvailableListener({ reader ->
                if (_latestFrame == null) {
                    captureFrame()
                } else {
                    try {
                        reader.acquireLatestImage()?.close()
                    } catch (_: Exception) {
                        // ignore drain errors
                    }
                }
            }, captureHandler)

            // Fallback if no image-available callback fires quickly
            captureHandler?.postDelayed({
                if (_latestFrame == null) {
                    captureFrame()
                }
            }, 400)

            Log.d(TAG, "Screen capture started ${captureWidth}x$captureHeight")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start capture: ${e.message}", e)
            releaseProjection(context)
        }
    }

    /**
     * Invoked from [Activity.onActivityResult] after the system consent dialog.
     */
    fun onScreenCapturePermissionResult(granted: Boolean) {
        if (granted) {
            val cb = _captureCompletionCallback
            _captureCompletionCallback = null
            cb?.invoke(true)
        } else {
            val cb = _captureCompletionCallback
            _captureCompletionCallback = null
            cb?.invoke(false)
        }
    }

    /**
     * Waits until a frame is available (or timeout), then invokes [onReady].
     */
    fun waitForFirstFrame(timeoutMs: Long = 2500L, onReady: () -> Unit) {
        if (_latestFrame != null || AssistantActivity.latestScreenshot != null) {
            onReady()
            return
        }
        _firstFrameCallback = onReady
        // Use main looper so timeout works even before captureHandler exists
        // (API 34+ delays beginProjection until MediaProjection FGS is ready).
        Handler(Looper.getMainLooper()).postDelayed({
            if (_firstFrameCallback != null) {
                Log.w(TAG, "First frame wait timed out after ${timeoutMs}ms")
                val cb = _firstFrameCallback
                _firstFrameCallback = null
                cb?.invoke()
            }
        }, timeoutMs)
    }

    private fun notifyFirstFrame() {
        val cb = _firstFrameCallback
        _firstFrameCallback = null
        cb?.invoke()
    }

    private fun resolveDisplaySize(context: Context) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val wm = context.getSystemService(WindowManager::class.java)
                val bounds = wm.currentWindowMetrics.bounds
                captureWidth = bounds.width().coerceAtLeast(1)
                captureHeight = bounds.height().coerceAtLeast(1)
            } else {
                val metrics = context.resources.displayMetrics
                captureWidth = metrics.widthPixels.coerceAtLeast(1)
                captureHeight = metrics.heightPixels.coerceAtLeast(1)
            }
            // Cap very large displays to keep PNG size reasonable
            val maxDim = 1920
            if (captureWidth > maxDim || captureHeight > maxDim) {
                val scale = maxDim.toFloat() / maxOf(captureWidth, captureHeight)
                captureWidth = (captureWidth * scale).toInt().coerceAtLeast(1)
                captureHeight = (captureHeight * scale).toInt().coerceAtLeast(1)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to resolve display size: ${e.message}")
            captureWidth = 1080
            captureHeight = 2400
        }
    }

    private fun captureFrame() {
        val reader = imageReader ?: return
        var image: Image? = null
        try {
            image = reader.acquireLatestImage()
            if (image == null) {
                Log.w(TAG, "No image available in ImageReader")
                return
            }

            val plane = image.planes[0]
            val buffer = plane.buffer
            val pixelStride = plane.pixelStride
            val rowStride = plane.rowStride
            val rowPadding = rowStride - pixelStride * captureWidth

            val bitmap = if (rowPadding == 0 && pixelStride == 4) {
                Bitmap.createBitmap(captureWidth, captureHeight, Bitmap.Config.ARGB_8888).also {
                    it.copyPixelsFromBuffer(buffer)
                }
            } else {
                // Account for row padding used by many GPU vendors
                val bitmapWidth = captureWidth + rowPadding / pixelStride
                val padded = Bitmap.createBitmap(
                    bitmapWidth,
                    captureHeight,
                    Bitmap.Config.ARGB_8888,
                )
                padded.copyPixelsFromBuffer(buffer)
                Bitmap.createBitmap(padded, 0, 0, captureWidth, captureHeight).also {
                    padded.recycle()
                }
            }

            val stream = ByteArrayOutputStream()
            // JPEG keeps payloads smaller for vision + MethodChannel
            bitmap.compress(Bitmap.CompressFormat.JPEG, 75, stream)
            _latestFrame = stream.toByteArray()

            AssistantActivity.latestScreenshot = _latestFrame
            AssistantActivity.latestTimestamp = System.currentTimeMillis()

            bitmap.recycle()
            Log.d(TAG, "Captured frame: ${_latestFrame!!.size} bytes")
            notifyFirstFrame()
        } catch (e: Exception) {
            Log.e(TAG, "Error capturing frame: ${e.message}", e)
        } finally {
            try {
                image?.close()
            } catch (_: Exception) {
            }
        }
    }

    private fun requestScreenCapture(activity: Activity) {
        try {
            val manager =
                activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            activity.startActivityForResult(
                manager.createScreenCaptureIntent(),
                REQUEST_SCREEN_CAPTURE,
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to request screen capture: ${e.message}")
            onScreenCapturePermissionResult(false)
        }
    }

    fun stopCapture() {
        isCapturing = false
        Log.d(TAG, "Screen capture paused (projection kept alive)")
    }

    fun releaseProjection(context: Context? = null) {
        isCapturing = false
        try {
            mediaProjection?.stop()
        } catch (_: Exception) {
        }
        mediaProjection = null
        try {
            imageReader?.close()
        } catch (_: Exception) {
        }
        imageReader = null
        captureThread?.quitSafely()
        captureThread = null
        captureHandler = null
        if (context != null) {
            try {
                MediaProjectionService.stop(context)
            } catch (_: Exception) {
            }
        }
        Log.d(TAG, "Screen capture fully released")
    }
}
