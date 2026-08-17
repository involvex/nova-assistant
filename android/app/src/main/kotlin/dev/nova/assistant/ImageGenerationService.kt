package dev.nova.assistant

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.MethodChannel

/**
 * ImageGenerationService — on-device diffusion via LiteRT multi-graph pipeline.
 *
 * This is a Phase 1 skeleton. Real inference requires Phase 0 feasibility
 * verification (LiteRT CompiledModel multi-graph API on the target device).
 *
 * Methods throw UnsupportedOperationException until the native pipeline
 * is implemented and the LiteRT TFLite dependency is added.
 */
object ImageGenerationService {
  private const val TAG = "ImageGenerationService"
  private const val CHANNEL = "dev.nova.assistant/image_gen"

  private var modelLoaded = false

  fun registerWith(messenger: io.flutter.plugin.common.BinaryMessenger, context: Context) {
    MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
      try {
        when (call.method) {
          "generateImage" -> {
            val prompt = call.argument<String>("prompt")
              ?: throw IllegalArgumentException("prompt required")
            val size = call.argument<Int>("size") ?: 512
            val seed = call.argument<Int>("seed")
            val model = call.argument<String>("model")

            result.success(generateImage(context, prompt, size, seed, model))
          }
          "isModelInstalled" -> {
            val model = call.argument<String>("model")
            result.success(isModelInstalled(context, model))
          }
          "getInstalledModels" -> {
            result.success(getInstalledModels(context))
          }
          else -> result.notImplemented()
        }
      } catch (e: Exception) {
        Log.e(TAG, "Method ${call.method} failed: ${e.message}")
        result.error("IMG_GEN_ERROR", e.message, null)
      }
    }
  }

  private fun generateImage(
    context: Context,
    prompt: String,
    size: Int,
    seed: Int?,
    model: String?,
  ): ByteArray? {
    if (!modelLoaded) {
      throw UnsupportedOperationException(
        "Image generation pipeline not initialized. " +
            "Phase 0 LiteRT multi-graph feasibility verification required."
      )
    }
    throw UnsupportedOperationException(
      "Diffusion inference not yet implemented. " +
          "Requires LiteRT CompiledModel multi-graph API + NNAPI delegate."
    )
  }

  private fun isModelInstalled(context: Context, model: String?): Boolean {
    if (model == null) return false
    val docsDir = context.getExternalFilesDir(null) ?: context.filesDir
    val modelDir = java.io.File(docsDir, "diffusion_models")
    if (!modelDir.exists()) return false
    val expectedFile = java.io.File(modelDir, "$model.tflite")
    return expectedFile.exists()
  }

  private fun getInstalledModels(context: Context): List<String> {
    val docsDir = context.getExternalFilesDir(null) ?: context.filesDir
    val modelDir = java.io.File(docsDir, "diffusion_models")
    if (!modelDir.exists()) return emptyList()

    val installed = mutableListOf<String>()
    modelDir.listFiles()?.forEach { file ->
      if (file.extension.equals("tflite", ignoreCase = true)) {
        val baseName = file.nameWithoutExtension
        if (ImageGenerationModels.isSupportedModel(baseName)) {
          installed.add(baseName)
        }
      }
    }
    return installed
  }
}
