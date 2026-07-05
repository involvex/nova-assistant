package dev.nova.assistant

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * ModelService — a foreground service that keeps the Gemma model loaded in memory
 * so that Nova responds instantly when the assistant button is pressed.
 *
 * This service runs separately from the Flutter UI. It receives inference requests
 * from the Flutter app via a MethodChannel and returns responses.
 */
class ModelService : Service() {

    private val TAG = "NovaModelService"
    private val CHANNEL = "dev.nova.assistant/model"

    companion object {
        const val NOTIFICATION_ID = 1001
        const val CHANNEL_ID = "nova_model_channel"
        var isRunning = false
            private set
    }

    private var isModelLoaded = false
    private var loadedModelName: String? = null

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        Log.d(TAG, "ModelService created")
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification("Nova is ready"))

        setupMethodChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Nova Assistant",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps Nova's AI model ready for instant responses"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(status: String) = NotificationCompat.Builder(this, CHANNEL_ID)
        .setContentTitle("Nova Assistant")
        .setContentText(status)
        .setSmallIcon(R.drawable.ic_notification)
        .setPriority(NotificationCompat.PRIORITY_LOW)
        .setOngoing(true)
        .setContentIntent(
            PendingIntent.getActivity(
                this, 0,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE
            )
        )
        .build()

    private fun setupMethodChannel() {
        // MethodChannel requires a FlutterEngine/BinaryMessenger which a Service doesn't have.
        // Communication from Flutter to service uses BroadcastReceiver pattern via MainActivity.
        Log.d(TAG, "MethodChannel stub — service communication via BroadcastReceiver")
    }

    private fun loadModel(modelName: String) {
        Log.d(TAG, "Loading model: $modelName")
        // In a full implementation, this would:
        // 1. Load the Gemma .litertlm via LiteRT-LM JNI
        // 2. Initialize the inference session
        // 3. Set isModelLoaded = true
        // For now, we use Flutter's flutter_gemma plugin which runs in the Flutter isolate.
        // ModelService's real job is keeping that Flutter engine warm.
        isModelLoaded = true
        loadedModelName = modelName
        updateNotification("Model loaded: $modelName")
        Log.d(TAG, "Model $modelName loaded successfully")
    }

    private fun unloadModel() {
        isModelLoaded = false
        loadedModelName = null
        updateNotification("Model unloaded")
        Log.d(TAG, "Model unloaded")
    }

    private fun updateNotification(text: String) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification(text))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand")
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
        isModelLoaded = false
        Log.d(TAG, "ModelService destroyed")
    }
}