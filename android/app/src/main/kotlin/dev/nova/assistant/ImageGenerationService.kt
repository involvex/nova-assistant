package dev.nova.assistant

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import java.io.File

object ImageGenerationService {
  private const val TAG = "ImageGenerationService"
  private const val CHANNEL = "dev.nova.assistant/image_gen"

  fun registerWith(messenger: io.flutter.plugin.common.BinaryMessenger, context: Context) {
    MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
      try {
        when (call.method) {
          "generateImage" -> {
            val prompt = call.argument<String>("prompt")
              ?: throw IllegalArgumentException("prompt required")
            val size = call.argument<Int>("size") ?: 512
            val seed = call.argument<Int>("seed")
            val modelName = call.argument<String>("model")

            result.success(generateImage(context, prompt, size, seed, modelName))
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

  private fun resolveModelType(modelName: String): DiffusionPipeline.ModelType? {
    return when {
      modelName.contains(ImageGenerationModels.MODEL_Z_IMAGE_TURBO, ignoreCase = true) ||
        modelName.equals("zImageTurbo", ignoreCase = true) ->
        DiffusionPipeline.ModelType.Z_IMAGE_TURBO
      modelName.contains(ImageGenerationModels.MODEL_FLUX_2_KLEIN, ignoreCase = true) ||
        modelName.equals("flux2Klein", ignoreCase = true) ->
        DiffusionPipeline.ModelType.FLUX_2_KLEIN
      else -> null
    }
  }

  private fun hasTflite(dir: File): Boolean {
    return dir.exists() && dir.isDirectory &&
      dir.listFiles()?.any { file ->
        file.isFile && file.extension.equals("tflite", ignoreCase = true)
      } == true
  }

  private fun generateImage(
    context: Context,
    prompt: String,
    size: Int,
    seed: Int?,
    modelName: String?,
  ): ByteArray? {
    val resolvedName = modelName
      ?: getInstalledModels(context).firstOrNull()
      ?: throw IllegalArgumentException("model name required")

    val modelType = resolveModelType(resolvedName)
      ?: throw IllegalArgumentException("Unsupported model: $resolvedName")

    val supportedSizes = listOf(256, 512, 1024)
    if (size !in supportedSizes) {
      throw IllegalArgumentException("Unsupported size: $size. Supported: $supportedSizes")
    }

    val modelDir = DiffusionPipeline.getModelDir(context, modelType)
    if (!hasTflite(modelDir)) {
      throw IllegalStateException("Model not installed: $resolvedName. Install it from Settings.")
    }

    val spec = when (modelType) {
      DiffusionPipeline.ModelType.Z_IMAGE_TURBO ->
        ImageGenerationModels.MODEL_SPECS[ImageGenerationModels.MODEL_Z_IMAGE_TURBO]
      DiffusionPipeline.ModelType.FLUX_2_KLEIN ->
        ImageGenerationModels.MODEL_SPECS[ImageGenerationModels.MODEL_FLUX_2_KLEIN]
    } ?: throw IllegalStateException("No model spec for $resolvedName")

    val config = DiffusionPipeline.GenerationConfig(
      modelType = modelType,
      size = size,
      seed = seed,
      steps = spec.defaultSteps,
      guidanceScale = spec.defaultGuidanceScale,
    )

    return try {
      val result = DiffusionPipeline.generateImage(context, config)
      result.imageBytes
    } catch (oom: OutOfMemoryError) {
      Log.e(TAG, "OOM during image generation", oom)
      DiffusionPipeline.unloadModel()
      throw IllegalStateException(
        "Out of memory during image generation. Try a smaller size (256x256) or restart the app."
      )
    } catch (e: Exception) {
      Log.e(TAG, "Image generation failed", e)
      throw IllegalStateException("Image generation failed: ${e.message}")
    }
  }

  private fun isModelInstalled(context: Context, model: String?): Boolean {
    if (model == null || model.isBlank()) {
      return getInstalledModels(context).isNotEmpty()
    }
    val modelType = resolveModelType(model) ?: return false
    return hasTflite(DiffusionPipeline.getModelDir(context, modelType))
  }

  private fun getInstalledModels(context: Context): List<String> {
    val installed = linkedSetOf<String>()
    for (root in DiffusionPipeline.diffusionRootCandidates(context)) {
      if (!root.exists() || !root.isDirectory) continue
      root.listFiles()?.forEach { dir ->
        if (dir.isDirectory && hasTflite(dir) && ImageGenerationModels.isSupportedModel(dir.name)) {
          installed.add(dir.name)
        }
      }
    }
    return installed.toList()
  }
}
