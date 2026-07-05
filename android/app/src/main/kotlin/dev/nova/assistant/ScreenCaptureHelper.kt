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
import android.hardware.display.VirtualDisplay
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

/**
 * Handles MediaProjection-based screen capture.
 * Provides the latest frame as a ByteArray (PNG) via a Flutter MethodChannel.
 */
object ScreenCaptureHelper {
    private const val TAG = "NovaScreenCapture"
    private const val CHANNEL = "dev.nova.assistant/screenshot"
    private const val WIDTH = 1080
    private const val HEIGHT = 2400
    private const val IMAGE_FORMAT = PixelFormat.RGBA_8888

    private var mediaProjection: MediaProjection? = null
    private var imageReader: ImageReader? = null
    private var captureThread: HandlerThread? = null
    private var captureHandler: Handler? = null
    private var isCapturing = false
    private var activityRef: Activity? = null

    // Latest captured frame
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
                "isCapturing" -> {
                    result.success(isCapturing)
                }
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

        val projectionManager = context.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = projectionManager.getMediaProjection(Activity.RESULT_OK, resultData)

        imageReader = ImageReader.newInstance(WIDTH, HEIGHT, ImageFormat.PRIVATE, 2)

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

        // Continuously poll frames
        captureHandler?.post(object : Runnable {
            override fun run() {
                captureFrame()
                if (isCapturing) {
                    captureHandler?.postDelayed(this, 1000) // 1 fps background capture
                }
            }
        })

        Log.d(TAG, "Screen capture started")
    }

    private fun captureFrame() {
        val reader = imageReader ?: return
        val image: Image? = reader.acquireLatestImage()
        image?.let {
            try {
                val buffer: ByteBuffer = it.planes[0].buffer
                val pixelFormat = Bitmap.Config.ARGB_8888
                val bitmap = Bitmap.createBitmap(WIDTH, HEIGHT, pixelFormat)
                bitmap.copyPixelsFromBuffer(buffer)

                // Compress to PNG
                val stream = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.PNG, 70, stream)
                _latestFrame = stream.toByteArray()

                AssistantActivity.latestScreenshot = _latestFrame
                AssistantActivity.latestTimestamp = System.currentTimeMillis()

                bitmap.recycle()
            } catch (e: Exception) {
                Log.e(TAG, "Error capturing frame: ${e.message}")
            } finally {
                it.close()
            }
        }
    }

    private fun requestScreenCapture(activity: Activity) {
        val manager = activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val intent = manager.createScreenCaptureIntent()
        activity.startActivityForResult(intent, 1001)
    }

    fun stopCapture() {
        isCapturing = false
        mediaProjection?.stop()
        mediaProjection = null
        imageReader?.close()
        imageReader = null
        captureThread?.quitSafely()
        captureThread = null
        captureHandler = null
        Log.d(TAG, "Screen capture stopped")
    }
}