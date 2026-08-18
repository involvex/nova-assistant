package dev.nova.assistant

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.MethodChannel

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

  private fun generateImage(
    context: Context,
    prompt: String,
    size: Int,
    seed: Int?,
    modelName: String?,
  ): ByteArray? {
    if (modelName == null) {
      throw IllegalArgumentException("model name required")
    }

    val modelType = when {
      modelName.contains(ImageGenerationModels.MODEL_Z_IMAGE_TURBO, ignoreCase = true) ->
        DiffusionPipeline.ModelType.Z_IMAGE_TURBO
      modelName.contains(ImageGenerationModels.MODEL_FLUX_2_KLEIN, ignoreCase = true) ->
        DiffusionPipeline.ModelType.FLUX_2_KLEIN
      else -> throw IllegalArgumentException("Unsupported model: $modelName")
    }

    val supportedSizes = listOf(256, 512, 1024)
    if (size !in supportedSizes) {
      throw IllegalArgumentException("Unsupported size: $size. Supported: $supportedSizes")
    }

    val modelDir = DiffusionPipeline.getModelDir(context, modelType)
    if (!modelDir.exists() || !modelDir.listFiles()?.any { it.extension.equals("tflite", ignoreCase = true) }!!) {
      throw IllegalStateException("Model not installed: $modelName. Install it from Settings.")
    }

    val spec = when (modelType) {
      DiffusionPipeline.ModelType.Z_IMAGE_TURBO ->
        ImageGenerationModels.MODEL_SPECS[ImageGenerationModels.MODEL_Z_IMAGE_TURBO]
      DiffusionPipeline.ModelType.FLUX_2_KLEIN ->
        ImageGenerationModels.MODEL_SPECS[ImageGenerationModels.MODEL_FLUX_2_KLEIN]
    } ?: throw IllegalStateException("No model spec for $modelName")

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
    if (model == null) return false
    val modelType = when {
      model.contains(ImageGenerationModels.MODEL_Z_IMAGE_TURBO, ignoreCase = true) ->
        DiffusionPipeline.ModelType.Z_IMAGE_TURBO
      model.contains(ImageGenerationModels.MODEL_FLUX_2_KLEIN, ignoreCase = true) ->
        DiffusionPipeline.ModelType.FLUX_2_KLEIN
      else -> return false
    }
    val modelDir = DiffusionPipeline.getModelDir(context, modelType)
    if (!modelDir.exists() || !modelDir.isDirectory) return false
    return modelDir.listFiles()?.any { file ->
      file.isFile && file.extension.equals("tflite", ignoreCase = true)
    } == true
  }

  private fun getInstalledModels(context: Context): List<String> {
    val docsDir = context.getExternalFilesDir(null) ?: context.filesDir
    val diffusionDir = java.io.File(docsDir, "diffusion_models")
    if (!diffusionDir.exists() || !diffusionDir.isDirectory) return emptyList()

    val installed = mutableListOf<String>()
    diffusionDir.listFiles()?.forEach { dir ->
      if (dir.isDirectory) {
        val hasTflite = dir.listFiles()?.any { file ->
          file.isFile && file.extension.equals("tflite", ignoreCase = true)
        } == true
        if (hasTflite && ImageGenerationModels.isSupportedModel(dir.name)) {
          installed.add(dir.name)
        }
      }
    }
    return installed
  }
}
