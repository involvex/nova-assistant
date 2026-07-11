package dev.nova.assistant

import android.app.Service
import android.content.Intent
import android.os.IBinder

/**
 * AssistantService — stub service for assistant-related manifest declarations.
 *
 * Does nothing; exists solely to satisfy manifest declarations for
 * android.speech.RecognitionService and android.voiceInteractionService.
 * The actual assistant functionality works via AssistantActivity's
 * ACTION_ASSIST intent filter + ROLE_ASSISTANT system role grant.
 */
class AssistantService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null
}