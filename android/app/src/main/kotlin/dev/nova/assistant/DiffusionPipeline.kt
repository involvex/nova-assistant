package dev.nova.assistant

import android.content.Context
import android.graphics.Bitmap
import android.util.Log
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.gpu.GpuDelegate
import java.io.ByteArrayOutputStream
import java.io.File

object DiffusionPipeline {
  private const val TAG = "DiffusionPipeline"

  enum class ModelType {
    Z_IMAGE_TURBO,
    FLUX_2_KLEIN,
  }

  data class PipelineResult(
    val imageBytes: ByteArray,
    val width: Int,
    val height: Int,
  ) {
    override fun equals(other: Any?): Boolean {
      if (this === other) return true
      if (javaClass != other?.javaClass) return false
      other as PipelineResult
      return width == other.width && height == other.height && imageBytes.contentEquals(other.imageBytes)
    }

    override fun hashCode(): Int {
      var result = imageBytes.contentHashCode()
      result = 31 * result + width
      result = 31 * result + height
      return result
    }
  }

  data class GenerationConfig(
    val modelType: ModelType,
    val size: Int,
    val seed: Int?,
    val steps: Int,
    val guidanceScale: Float,
  )

  private var loadedModelType: ModelType? = null
  private var textEncoderInterpreter: Interpreter? = null
  private var unetMainInterpreters: List<Interpreter> = emptyList()
  private var unetFinalInterpreter: Interpreter? = null
  private var vaeInterpreter: Interpreter? = null
  private var gpuDelegate: GpuDelegate? = null

  fun isModelLoaded(modelType: ModelType): Boolean {
    return loadedModelType == modelType
  }

  fun loadModel(context: Context, modelType: ModelType, onProgress: (String, Int) -> Unit = { _, _ -> }) {
    if (isModelLoaded(modelType)) {
      Log.d(TAG, "Model already loaded: $modelType")
      return
    }
    unloadModel()

    val modelDir = getModelDir(context, modelType)
    if (!modelDir.exists()) {
      throw IllegalStateException("Model directory not found: ${modelDir.absolutePath}")
    }

    val spec = when (modelType) {
      ModelType.Z_IMAGE_TURBO -> ImageGenerationModels.MODEL_SPECS[ImageGenerationModels.MODEL_Z_IMAGE_TURBO]
      ModelType.FLUX_2_KLEIN -> ImageGenerationModels.MODEL_SPECS[ImageGenerationModels.MODEL_FLUX_2_KLEIN]
    } ?: throw IllegalStateException("No model spec for $modelType")

    onProgress("Loading text encoder", 10)
    textEncoderInterpreter = createInterpreter(modelDir, spec.textEncoder)

    onProgress("Loading UNet main blocks", 30)
    unetMainInterpreters = spec.unetMain.map { fileName ->
      createInterpreter(modelDir, listOf(fileName))
    }

    onProgress("Loading UNet final block", 50)
    unetFinalInterpreter = createInterpreter(modelDir, spec.unetFinal)

    onProgress("Loading VAE decoder", 60)
    vaeInterpreter = createInterpreter(modelDir, spec.vae)

    loadedModelType = modelType
    onProgress("Model loaded", 100)
    Log.i(TAG, "Model loaded: $modelType")
  }

  fun unloadModel() {
    textEncoderInterpreter?.close()
    unetMainInterpreters.forEach { it.close() }
    unetFinalInterpreter?.close()
    vaeInterpreter?.close()
    gpuDelegate?.close()

    textEncoderInterpreter = null
    unetMainInterpreters = emptyList()
    unetFinalInterpreter = null
    vaeInterpreter = null
    gpuDelegate = null
    loadedModelType = null

    Log.d(TAG, "Model unloaded")
  }

  private fun createInterpreter(
    modelDir: File,
    fileNames: List<String>,
  ): Interpreter {
    val tfliteFiles = fileNames.map { File(modelDir, it) }
    for (file in tfliteFiles) {
      if (!file.exists()) {
        throw IllegalStateException("Model file not found: ${file.absolutePath}")
      }
    }

    val options = Interpreter.Options().apply {
      setNumThreads(4)
      try {
        gpuDelegate = GpuDelegate()
        addDelegate(gpuDelegate)
      } catch (e: Exception) {
        Log.w(TAG, "NNAPI GPU delegate unavailable, falling back to CPU: ${e.message}")
      }
    }

    val modelFile = tfliteFiles.first()
    return Interpreter(modelFile, options)
  }

  fun generateImage(
    context: Context,
    config: GenerationConfig,
    onProgress: (String, Int) -> Unit = { _, _ -> },
  ): PipelineResult {
    val modelDir = getModelDir(context, config.modelType)

    if (!isModelLoaded(config.modelType)) {
      loadModel(context, config.modelType, onProgress)
    }

    val spec = when (config.modelType) {
      ModelType.Z_IMAGE_TURBO -> ImageGenerationModels.MODEL_SPECS[ImageGenerationModels.MODEL_Z_IMAGE_TURBO]
      ModelType.FLUX_2_KLEIN -> ImageGenerationModels.MODEL_SPECS[ImageGenerationModels.MODEL_FLUX_2_KLEIN]
    } ?: throw IllegalStateException("No model spec for ${config.modelType}")

    onProgress("Preparing latents", 5)
    val latentHeight = config.size / spec.latentHeightFactor
    val latentWidth = config.size / spec.latentWidthFactor
    val latentChannels = spec.latentChannels

    val seed = config.seed ?: kotlin.random.Random.nextInt()
    val rng = kotlin.random.Random(seed)
    val latents = Array(latentHeight * latentWidth * latentChannels) {
      floatArrayOf((rng.nextFloat() - 0.5f) * 2f)
    }

    onProgress("Encoding prompt", 10)
    val textEmbeddings = encodePrompt(config.modelType, "A beautiful image")

    onProgress("Preparing scheduler", 15)
    val scheduler = DiffusionScheduler.createState()
    val timesteps = DiffusionScheduler.getTimestepsForInference(scheduler, config.steps)

    for ((stepIdx, timestep) in timesteps.withIndex()) {
      val progress = 15 + ((stepIdx + 1) * 70 / timesteps.size)
      onProgress("Denoising step ${stepIdx + 1}/${timesteps.size}", progress)

      val scaledLatents = scaleLatentsForTimestep(latents, timestep, scheduler)

      var noisePred: Array<FloatArray> = emptyArray()
      for ((blockIdx, interpreter) in unetMainInterpreters.withIndex()) {
        val blockInput = if (blockIdx == 0) scaledLatents else noisePred
        noisePred = runUnetBlock(interpreter, blockInput, textEmbeddings, timestep, latentHeight, latentWidth, latentChannels)
      }

      val finalNoise = runUnetFinal(unetFinalInterpreter!!, noisePred, textEmbeddings, timestep, latentHeight, latentWidth, latentChannels)

      val stepResult = DiffusionScheduler.step(
        state = scheduler,
        timestep = timestep,
        latents = latents,
        predictedNoise = finalNoise,
        guidanceScale = config.guidanceScale,
      )
      for (i in latents.indices) {
        latents[i] = stepResult.nextLatents[i]
      }
    }

    onProgress("Decoding image", 90)
    val imageBytes = decodeLatentsToPng(vaeInterpreter!!, latents, latentHeight, latentWidth, latentChannels, config.size)

    onProgress("Complete", 100)
    return PipelineResult(imageBytes = imageBytes, width = config.size, height = config.size)
  }

  private fun encodePrompt(
    modelType: ModelType,
    prompt: String,
  ): Array<FloatArray> {
    val encoder = textEncoderInterpreter ?: throw IllegalStateException("Text encoder not loaded")
    val promptBytes = prompt.toByteArray(Charsets.UTF_8)

    val inputShape = encoder.getInputTensor(0).shape()
    val outputShape = encoder.getOutputTensor(0).shape()

    val inputArray = when {
      inputShape.size == 2 && inputShape[1] == 1 -> {
        val seqLen = inputShape[0]
        Array(seqLen) { floatArrayOf(promptBytes.getOrElse(it % promptBytes.size) { 0 }.toFloat()) }
      }
      inputShape.size == 2 && inputShape[1] > 1 -> {
        val seqLen = inputShape[0]
        val dim = inputShape[1]
        Array(seqLen) { i ->
          val base = if (i < promptBytes.size) promptBytes[i].toFloat() else 0f
          FloatArray(dim) { j -> if (j == 0) base else 0f }
        }
      }
      else -> {
        val total = inputShape.reduceOrNull { a, b -> a * b } ?: 1
        Array(total) { floatArrayOf(promptBytes.getOrElse(it % promptBytes.size) { 0 }.toFloat()) }
      }
    }

    val outputArray = Array(outputShape[0]) { FloatArray(outputShape[1]) }
    encoder.run(inputArray, outputArray)
    return outputArray
  }

  private fun runUnetBlock(
    interpreter: Interpreter,
    latents: Array<FloatArray>,
    embeddings: Array<FloatArray>,
    timestep: Int,
    height: Int,
    width: Int,
    channels: Int,
  ): Array<FloatArray> {
    val inputShape = interpreter.getInputTensor(0).shape()
    val outputShape = interpreter.getOutputTensor(0).shape()

    val spatialSize = height * width
    val combinedSize = spatialSize * channels + embeddings.size * embeddings.first().size + 1

    val input = Array(combinedSize) { FloatArray(1) }
    var offset = 0
    for (i in latents.indices) {
      input[offset++] = floatArrayOf(latents[i].first())
    }
    for (i in embeddings.indices) {
      for (j in embeddings[i].indices) {
        input[offset++] = floatArrayOf(embeddings[i][j])
      }
    }
    input[offset] = floatArrayOf(timestep.toFloat())

    val outputSize = outputShape.reduceOrNull { a, b -> a * b } ?: 1
    val output = Array(outputSize) { FloatArray(1) }
    interpreter.run(input, output)
    return output
  }

  private fun runUnetFinal(
    interpreter: Interpreter,
    latents: Array<FloatArray>,
    embeddings: Array<FloatArray>,
    timestep: Int,
    height: Int,
    width: Int,
    channels: Int,
  ): Array<FloatArray> {
    val inputShape = interpreter.getInputTensor(0).shape()
    val outputShape = interpreter.getOutputTensor(0).shape()

    val spatialSize = height * width
    val combinedSize = spatialSize * channels + embeddings.size * embeddings.first().size + 1

    val input = Array(combinedSize) { FloatArray(1) }
    var offset = 0
    for (i in latents.indices) {
      input[offset++] = floatArrayOf(latents[i].first())
    }
    for (i in embeddings.indices) {
      for (j in embeddings[i].indices) {
        input[offset++] = floatArrayOf(embeddings[i][j])
      }
    }
    input[offset] = floatArrayOf(timestep.toFloat())

    val outputSize = outputShape.reduceOrNull { a, b -> a * b } ?: 1
    val output = Array(outputSize) { FloatArray(1) }
    interpreter.run(input, output)
    return output
  }

  private fun scaleLatentsForTimestep(
    latents: Array<FloatArray>,
    timestep: Int,
    scheduler: DiffusionScheduler.SchedulerState,
  ): Array<FloatArray> {
    val alphaProd = scheduler.alphasCumprod.getOrElse(timestep) { 1f }
    val scale = kotlin.math.sqrt(alphaProd)
    return Array(latents.size) { idx ->
      val current = latents[idx]
      FloatArray(current.size) { i -> current[i] * scale }
    }
  }

  private fun decodeLatentsToPng(
    interpreter: Interpreter,
    latents: Array<FloatArray>,
    latentHeight: Int,
    latentWidth: Int,
    latentChannels: Int,
    outputSize: Int,
  ): ByteArray {
    val inputShape = interpreter.getInputTensor(0).shape()
    val expectedInputSize = inputShape.reduceOrNull { a, b -> a * b } ?: latents.size
    val input = Array(expectedInputSize) { FloatArray(1) }
    for (i in latents.indices) {
      input[i] = floatArrayOf(latents[i].first())
    }

    val outputShape = interpreter.getOutputTensor(0).shape()
    val expectedOutputSize = outputShape.reduceOrNull { a, b -> a * b } ?: outputSize * outputSize * 3
    val output = Array(expectedOutputSize) { FloatArray(1) }
    interpreter.run(input, output)

    val pixels = IntArray(outputSize * outputSize)
    for (i in pixels.indices) {
      val r = (output.getOrElse(i * 3) { floatArrayOf(0f) }.first().coerceIn(0f, 1f) * 255).toInt()
      val g = (output.getOrElse(i * 3 + 1) { floatArrayOf(0f) }.first().coerceIn(0f, 1f) * 255).toInt()
      val b = (output.getOrElse(i * 3 + 2) { floatArrayOf(0f) }.first().coerceIn(0f, 1f) * 255).toInt()
      pixels[i] = 0xFF shl 24 or (r shl 16) or (g shl 8) or b
    }

    val bitmap = Bitmap.createBitmap(outputSize, outputSize, Bitmap.Config.ARGB_8888)
    bitmap.setPixels(pixels, 0, outputSize, 0, 0, outputSize, outputSize)

    val stream = ByteArrayOutputStream()
    bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
    bitmap.recycle()
    return stream.toByteArray()
  }

  fun getModelDir(context: Context, modelType: ModelType): File {
    val docsDir = context.getExternalFilesDir(null) ?: context.filesDir
    val modelDirName = when (modelType) {
      ModelType.Z_IMAGE_TURBO -> ImageGenerationModels.MODEL_Z_IMAGE_TURBO
      ModelType.FLUX_2_KLEIN -> ImageGenerationModels.MODEL_FLUX_2_KLEIN
    }
    return File(File(docsDir, "diffusion_models"), modelDirName)
  }
}
