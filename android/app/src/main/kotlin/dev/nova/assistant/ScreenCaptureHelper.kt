package dev.nova.assistant

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageFormat
import android.graphics.PixelFormat
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Handles MediaProjection-based screen capture.
 * Uses RGBA_8888 for reliable direct pixel access on all GPU vendors.
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

    private var _latestFrame: ByteArray? = null
    val latestFrame: ByteArray? get() = _latestFrame

    fun registerWith(messenger: BinaryMessenger, activity: Activity) {
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

            // RGBA_8888 has directly readable pixel planes on all GPU vendors
            imageReader = ImageReader.newInstance(WIDTH, HEIGHT, PixelFormat.RGBA_8888, 2)

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

            // Capture a single frame after permission is granted
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
            image = reader.acquireLatestImage()
            if (image == null) {
                Log.w(TAG, "No image available in ImageReader")
                return
            }

            // RGBA_8888: planes[0] contains raw RGBA bytes directly
            val buffer = image.planes[0].buffer
            val pixelStride = image.planes[0].pixelStride
            val rowStride = image.planes[0].rowStride

            // Convert RGBA to Bitmap
            val bitmap = Bitmap.createBitmap(
                WIDTH, HEIGHT, Bitmap.Config.ARGB_8888
            )
            bitmap.copyPixelsFromBuffer(buffer)

            // Compress to PNG for Flutter
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 70, stream)
            _latestFrame = stream.toByteArray()

            AssistantActivity.latestScreenshot = _latestFrame
            AssistantActivity.latestTimestamp = System.currentTimeMillis()

            bitmap.recycle()
            Log.d(TAG, "Captured frame: ${_latestFrame!!.size} bytes")
        } catch (e: Exception) {
            Log.e(TAG, "Error capturing frame: ${e.message}")
        } finally {
            try { image?.close() } catch (_: Exception) {}
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
        try { mediaProjection?.stop() } catch (_: Exception) {}
        mediaProjection = null
        try { imageReader?.close() } catch (_: Exception) {}
        imageReader = null
        captureThread?.quitSafely()
        captureThread = null
        captureHandler = null
        Log.d(TAG, "Screen capture stopped")
    }
}