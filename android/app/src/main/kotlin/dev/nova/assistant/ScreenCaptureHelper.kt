package dev.nova.assistant

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.PixelFormat
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Handles MediaProjection-based screen capture.
 * Provides the latest frame as a ByteArray (PNG) via a Flutter MethodChannel.
 */
object ScreenCaptureHelper {
    private const val TAG = "NovaScreenCapture"
    private const val CHANNEL = "dev.nova.assistant/screenshot"
    private const val WIDTH = 1080
    private const val HEIGHT = 2400

    private var mediaProjection: MediaProjection? = null
    private var imageReader: ImageReader? = null
    private var captureThread: HandlerThread? = null
    private var captureHandler: Handler? = null
    private var isCapturing = false
    private var activityRef: Activity? = null

    private var _latestFrame: ByteArray? = null
    val latestFrame: ByteArray? get() = _latestFrame

    fun registerWith(messenger: BinaryMessenger, activity: Activity) {
        activityRef = activity
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getLatestScreenshot" -> {
                    val frame = _latestFrame
                    if (frame != null) {
                        Log.d(TAG, "Returning screenshot: ${frame.size} bytes")
                        result.success(frame)
                    } else {
                        result.success(null)
                    }
                }
                "isCapturing" -> result.success(isCapturing)
                "requestCapture" -> {
                    if (mediaProjection == null) {
                        requestScreenCapture(activity)
                        result.success(false)
                    } else {
                        result.success(true)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun startCapture(context: Context, resultData: android.content.Intent) {
        if (isCapturing) return

        try {
            val projectionManager = context.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            mediaProjection = projectionManager.getMediaProjection(Activity.RESULT_OK, resultData)

            // Use JPEG format — universally readable across GPU vendors
            imageReader = ImageReader.newInstance(WIDTH, HEIGHT, ImageFormat.JPEG, 2)

            val surface: Surface = imageReader!!.surface

            captureThread = HandlerThread("NovaScreenCapture").apply { start() }
            captureHandler = Handler(captureThread!!.looper)

            mediaProjection?.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    Log.d(TAG, "MediaProjection stopped")
                    stopCapture()
                }
            }, captureHandler)

            mediaProjection?.createVirtualDisplay(
                "NovaScreenCapture",
                WIDTH, HEIGHT,
                context.resources.displayMetrics.densityDpi,
                0x0002,
                surface,
                null,
                captureHandler
            )

            isCapturing = true

            // Single capture after permission grant — not continuous polling
            captureHandler?.postDelayed({
                captureFrame()
            }, 500)

            Log.d(TAG, "Screen capture started")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start capture: ${e.message}")
            stopCapture()
        }
    }

    private fun captureFrame() {
        val reader = imageReader ?: return
        var image: Image? = null
        try {
            image = reader.acquireLatestImage() ?: return

            // JPEG format: planes[0] contains the compressed JPEG data
            val buffer = image.planes[0].buffer
            val bytes = ByteArray(buffer.remaining())
            buffer.get(bytes)

            _latestFrame = bytes
            AssistantActivity.latestScreenshot = bytes
            AssistantActivity.latestTimestamp = System.currentTimeMillis()

            Log.d(TAG, "Captured frame: ${bytes.size} bytes")
        } catch (e: Exception) {
            Log.e(TAG, "Error capturing frame: ${e.message}")
        } finally {
            image?.close()
        }
    }

    private fun requestScreenCapture(activity: Activity) {
        try {
            val manager = activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            activity.startActivityForResult(manager.createScreenCaptureIntent(), 1001)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to request screen capture: ${e.message}")
        }
    }

    fun stopCapture() {
        isCapturing = false
        try {
            mediaProjection?.stop()
        } catch (_: Exception) {}
        mediaProjection = null
        try {
            imageReader?.close()
        } catch (_: Exception) {}
        imageReader = null
        captureThread?.quitSafely()
        captureThread = null
        captureHandler = null
        Log.d(TAG, "Screen capture stopped")
    }
}
