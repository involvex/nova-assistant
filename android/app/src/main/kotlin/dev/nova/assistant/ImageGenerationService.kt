package dev.nova.assistant

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

object ImageGenerationService {
  private const val TAG = "ImageGenerationService"
  private const val CHANNEL = "dev.nova.assistant/image_gen"

  private val mainHandler = Handler(Looper.getMainLooper())
  private val worker = Executors.newSingleThreadExecutor { r ->
    Thread(r, "nova-image-gen").apply { isDaemon = true }
  }
  private val busy = AtomicBoolean(false)

  fun registerWith(messenger: io.flutter.plugin.common.BinaryMessenger, context: Context) {
    val appContext = context.applicationContext
    MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "generateImage" -> {
          val prompt = call.argument<String>("prompt")
          if (prompt.isNullOrBlank()) {
            result.error("IMG_GEN_ERROR", "prompt required", null)
            return@setMethodCallHandler
          }
          val size = call.argument<Int>("size") ?: 512
          val seed = call.argument<Int>("seed")
          val modelName = call.argument<String>("model")
          val modelDir = call.argument<String>("modelDir")

          if (!busy.compareAndSet(false, true)) {
            result.error("IMG_GEN_ERROR", "Image generation already in progress", null)
            return@setMethodCallHandler
          }

          worker.execute {
            try {
              val bytes = generateImage(appContext, prompt, size, seed, modelName, modelDir)
              mainHandler.post { result.success(bytes) }
            } catch (oom: OutOfMemoryError) {
              Log.e(TAG, "OOM during image generation", oom)
              DiffusionPipeline.unloadModel()
              System.gc()
              mainHandler.post {
                result.error(
                  "IMG_GEN_ERROR",
                  "Out of memory. Close other apps, use 256x256, and try again.",
                  null,
                )
              }
            } catch (t: Throwable) {
              Log.e(TAG, "generateImage failed: ${t.message}", t)
              DiffusionPipeline.unloadModel()
              mainHandler.post {
                result.error("IMG_GEN_ERROR", t.message, null)
              }
            } finally {
              busy.set(false)
            }
          }
        }
        "isModelInstalled" -> {
          try {
            val model = call.argument<String>("model")
            val modelDir = call.argument<String>("modelDir")
            result.success(isModelInstalled(appContext, model, modelDir))
          } catch (t: Throwable) {
            Log.e(TAG, "isModelInstalled failed: ${t.message}", t)
            result.error("IMG_GEN_ERROR", t.message, null)
          }
        }
        "getInstalledModels" -> {
          try {
            result.success(getInstalledModels(appContext))
          } catch (t: Throwable) {
            Log.e(TAG, "getInstalledModels failed: ${t.message}", t)
            result.error("IMG_GEN_ERROR", t.message, null)
          }
        }
        "unloadDiffusion" -> {
          worker.execute {
            try {
              DiffusionPipeline.unloadModel()
              System.gc()
              mainHandler.post { result.success(true) }
            } catch (t: Throwable) {
              mainHandler.post { result.error("IMG_GEN_ERROR", t.message, null) }
            }
          }
        }
        else -> result.notImplemented()
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

  private fun resolveModelDirectory(
    context: Context,
    modelType: DiffusionPipeline.ModelType,
    modelDirOverride: String?,
  ): File {
    if (!modelDirOverride.isNullOrBlank()) {
      val override = File(modelDirOverride)
      if (DiffusionPipeline.hasTfliteWeights(override)) {
        Log.d(TAG, "Using Dart modelDir override: ${override.absolutePath}")
        return override
      }
      Log.w(
        TAG,
        "Dart modelDir override missing tflite: ${override.absolutePath}",
      )
    }
    return DiffusionPipeline.getModelDir(context, modelType)
  }

  private fun generateImage(
    context: Context,
    prompt: String,
    size: Int,
    seed: Int?,
    modelName: String?,
    modelDirOverride: String?,
  ): ByteArray? {
    val resolvedName = modelName
      ?: getInstalledModels(context).firstOrNull()
      ?: throw IllegalArgumentException("model name required")

    val modelType = resolveModelType(resolvedName)
      ?: throw IllegalArgumentException("Unsupported model: $resolvedName")

    // Cap at 512 — 1024 + warm LLM reliably OOMs mid-range phones.
    val safeSize = when {
      size <= 256 -> 256
      size <= 512 -> 512
      else -> {
        Log.w(TAG, "Clamping requested size $size → 512 to reduce OOM risk")
        512
      }
    }

    val modelDir = resolveModelDirectory(context, modelType, modelDirOverride)
    if (!DiffusionPipeline.hasTfliteWeights(modelDir)) {
      val searched = DiffusionPipeline.diffusionModelDirCandidates(
        context,
        when (modelType) {
          DiffusionPipeline.ModelType.Z_IMAGE_TURBO ->
            ImageGenerationModels.MODEL_Z_IMAGE_TURBO
          DiffusionPipeline.ModelType.FLUX_2_KLEIN ->
            ImageGenerationModels.MODEL_FLUX_2_KLEIN
        },
      ).joinToString { it.absolutePath }
      throw IllegalStateException(
        "Model not installed: $resolvedName (looked in $searched). Install it from Settings.",
      )
    }

    val spec = when (modelType) {
      DiffusionPipeline.ModelType.Z_IMAGE_TURBO ->
        ImageGenerationModels.MODEL_SPECS[ImageGenerationModels.MODEL_Z_IMAGE_TURBO]
      DiffusionPipeline.ModelType.FLUX_2_KLEIN ->
        ImageGenerationModels.MODEL_SPECS[ImageGenerationModels.MODEL_FLUX_2_KLEIN]
    } ?: throw IllegalStateException("No model spec for $resolvedName")

    val config = DiffusionPipeline.GenerationConfig(
      modelType = modelType,
      size = safeSize,
      seed = seed,
      steps = spec.defaultSteps,
      guidanceScale = spec.defaultGuidanceScale,
      prompt = prompt,
    )

    return try {
      val result = DiffusionPipeline.generateImage(
        context,
        config,
        modelDirOverride = modelDir,
      )
      result.imageBytes
    } finally {
      // Free ~GB of TFLite mmap ASAP so chat can reload Gemma.
      DiffusionPipeline.unloadModel()
      System.gc()
    }
  }

  private fun isModelInstalled(
    context: Context,
    model: String?,
    modelDirOverride: String?,
  ): Boolean {
    if (model == null || model.isBlank()) {
      return getInstalledModels(context).isNotEmpty()
    }
    val modelType = resolveModelType(model) ?: return false
    return DiffusionPipeline.hasTfliteWeights(
      resolveModelDirectory(context, modelType, modelDirOverride),
    )
  }

  private fun getInstalledModels(context: Context): List<String> {
    val installed = linkedSetOf<String>()
    for (root in DiffusionPipeline.diffusionRootCandidates(context)) {
      if (!root.exists() || !root.isDirectory) continue
      root.listFiles()?.forEach { dir ->
        if (dir.isDirectory &&
          DiffusionPipeline.hasTfliteWeights(dir) &&
          ImageGenerationModels.isSupportedModel(dir.name)
        ) {
          installed.add(dir.name)
        }
      }
    }
    return installed.toList()
  }
}
