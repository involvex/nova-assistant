package dev.nova.assistant

import android.os.Bundle
import android.speech.RecognitionService

/**
 * AssistantService — satisfies BIND_ASSISTANT_SERVICE so Nova can be
 * selected as the system default assistant on Android 14+.
 *
 * This is a stub implementation; actual voice input uses the system's
 * recognizer. The service exists solely to fulfill the binding requirement
 * for the assistant role.
 */
class AssistantService : RecognitionService() {

    override fun onReadyForSpeech(params: Bundle?) {}

    override fun onBeginningOfSpeech() {}

    override fun onEndOfSpeech() {}

    override fun onRmsChanged(rmsdB: Float) {}

    override fun onBufferReceived(buffer: ByteArray?) {}

    override fun onResults(results: Bundle?) {}

    override fun onPartialResults(partialResults: Bundle?) {}

    override fun onError(error: Int) {}
}