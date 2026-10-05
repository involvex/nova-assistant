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
    val prompt: String = "",
  )

  private var loadedModelType: ModelType? = null
  private var textEncoderInterpreter: Interpreter? = null
  private var unetMainInterpreters: List<Interpreter> = emptyList()
  private var unetFinalInterpreter: Interpreter? = null
  private var vaeInterpreter: Interpreter? = null
  private val gpuDelegates = mutableListOf<GpuDelegate>()
  /** GPU delegate disabled: JNI/R8 + peak VRAM with Gemma caused process kills. */
  @Volatile private var tryGpuDelegate = false

  fun isModelLoaded(modelType: ModelType): Boolean {
    return loadedModelType == modelType
  }

  fun loadModel(
    context: Context,
    modelType: ModelType,
    onProgress: (String, Int) -> Unit = { _, _ -> },
    modelDirOverride: File? = null,
  ) {
    if (isModelLoaded(modelType)) {
      Log.d(TAG, "Model already loaded: $modelType")
      return
    }
    unloadModel()

    val modelDir = modelDirOverride ?: getModelDir(context, modelType)
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
    Log.i(TAG, "Model loaded: $modelType (gpu=${gpuDelegates.isNotEmpty()})")
  }

  fun unloadModel() {
    textEncoderInterpreter?.close()
    unetMainInterpreters.forEach { it.close() }
    unetFinalInterpreter?.close()
    vaeInterpreter?.close()
    for (delegate in gpuDelegates) {
      try {
        delegate.close()
      } catch (_: Throwable) {
        // ignore
      }
    }
    gpuDelegates.clear()

    textEncoderInterpreter = null
    unetMainInterpreters = emptyList()
    unetFinalInterpreter = null
    vaeInterpreter = null
    loadedModelType = null

    Log.d(TAG, "Model unloaded")
  }
  /**
   * Z-Image Turbo end-to-end run. Graphs are 256 px-fixed, so larger
   * requests clamp (a 512 silent misshape would be worse than a smaller
   * image). Interpreters open lazily per phase inside [ZImageTfliteGraphs]
   * and the pipeline releases each phase; the `finally` here is the
   * backstop for mid-run failures.
   */
  private fun generateZImage(
    config: GenerationConfig,
    modelDir: File,
    prompt: String,
    onProgress: (String, Int) -> Unit,
  ): PipelineResult {
    if (config.size != ZImagePipeline.SIZE_PX) {
      Log.w(TAG, "Z-Image graphs are 256px-fixed; clamping ${config.size} → 256")
    }

    val assetCheck = SafetensorsHeaderCheck.checkDerivedAssets(modelDir)
    if (assetCheck is SafetensorsHeaderCheck.CheckResult.Failed) {
      throw IllegalStateException(
        "Z-Image host assets failed pre-check:\n" +
          assetCheck.reasons.joinToString("\n") +
          "\nReinstall extra assets from Settings.",
      )
    }
    // Byte-level gate: shapes alone cannot catch a corrupt graph (qwen_enc
    // matched the published size exactly while emitting std-5e10 outputs),
    // and a bad 3.5 GB encoder wastes a multi-minute run producing static.
    val integrity = ZImageGraphIntegrity.verify(modelDir)
    if (integrity is ZImageGraphIntegrity.CheckResult.Failed) {
      throw IllegalStateException(
        "Z-Image graph files failed integrity check:\n" +
          integrity.reasons.joinToString("\n") +
          "\nDelete the listed files and reinstall the model from Settings.",
      )
    }
    val tokenizer = try {
      QwenBpeTokenizer.load(File(modelDir, "tokenizer"))
    } catch (e: IllegalArgumentException) {
      throw IllegalStateException(
        "Z-Image tokenizer unreadable: ${e.message}. Reinstall extra assets from Settings.",
        e,
      )
    }
    val tWeights = try {
      TEmbedderWeightsLoader.load(File(modelDir, "t_embedder.safetensors"))
    } catch (e: IllegalStateException) {
      throw IllegalStateException(
        "Z-Image t_embedder unreadable: ${e.message}. Reinstall extra assets from Settings.",
        e,
      )
    } catch (e: IllegalArgumentException) {
      throw IllegalStateException(
        "Z-Image t_embedder unreadable: ${e.message}. Reinstall extra assets from Settings.",
        e,
      )
    }

    val embedFile = File(modelDir, "embed_tokens.safetensors")
    // Build marker: bump when the Z-Image path changes so a logcat line
    // proves which code actually ran on the device.
    Log.d(TAG, "ZIMG-DIAG4 steps=${config.steps} guidance=${config.guidanceScale} size=${config.size}")
    val graphSizes = modelDir.listFiles()
      ?.filter { it.isFile && it.extension == "tflite" }
      ?.sortedBy { it.name }
      ?.joinToString(", ") { it.name + "=" + it.length() }
    Log.d(TAG, "ZIMG files: $graphSizes")
    val graphs = ZImageTfliteGraphs(modelDir)
    // Zero-probes: the previous run showed qwen_enc exploding to std 5e10
    // and embx to std 419 on valid inputs. Feeding zeros separates a broken
    // graph file/conversion (still explodes: weights or kernels are bad,
    // independent of any host input) from input-triggered divergence
    // (zeros come back at bias scale, so the host inputs are the trigger).
    val qwenZero = graphs.qwenEnc(
      FloatArray(ZImageHostLoop.EMBED_SEQUENCE_TOKENS * ZImageHostLoop.EMBED_DIM),
    )
    Log.d(TAG, "ZIMG " + ZImagePipeline.tensorStats("qwenZero", qwenZero))
    val embxZero = graphs.embx(FloatArray(ZImagePipeline.X_IMG_SIZE))
    Log.d(TAG, "ZIMG " + ZImagePipeline.tensorStats("embxZero", embxZero))
    try {
      val rgb = ZImagePipeline.generate(
        graphs = graphs,
        // Chat-templated, not raw: Z-Image's text encoder was trained on
        // apply_chat_template output. A bare prompt leaves it conditioning on
        // out-of-distribution text and the sample degenerates to noise.
        tokenize = { text ->
          val ids = tokenizer.encodeChatPrompt(text)
          Log.d(TAG, "ZIMG tokens n=${ids.size} head=${ids.take(12).joinToString(",")} tail=${ids.takeLast(6).joinToString(",")}")
          ids
        },
        rowsOf = { ids ->
          val rows = embedRows(embedFile, ids)
          var rmin = Float.MAX_VALUE
          var rmax = -Float.MAX_VALUE
          for (row in rows) for (v in row) {
            if (v < rmin) rmin = v
            if (v > rmax) rmax = v
          }
          Log.d(TAG, "ZIMG embedRows ids=${ids.size} range=[$rmin,$rmax]")
          rows
        },
        weights = tWeights,
        req = ZImagePipeline.Request(
          prompt = prompt,
          steps = config.steps,
          guidance = config.guidanceScale,
          seed = config.seed?.toLong() ?: kotlin.random.Random.nextLong(),
        ),
        onProgress = onProgress,
        onLog = { line -> Log.d(TAG, "ZIMG $line") },
      )
      val pixels = ZImageHostLoop.chwToArgb(rgb, ZImagePipeline.SIZE_PX, ZImagePipeline.SIZE_PX)
      val bitmap = Bitmap.createBitmap(
        ZImagePipeline.SIZE_PX,
        ZImagePipeline.SIZE_PX,
        Bitmap.Config.ARGB_8888,
      )
      bitmap.setPixels(
        pixels, 0, ZImagePipeline.SIZE_PX, 0, 0,
        ZImagePipeline.SIZE_PX, ZImagePipeline.SIZE_PX,
      )
      val stream = ByteArrayOutputStream()
      bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
      bitmap.recycle()
      return PipelineResult(
        imageBytes = stream.toByteArray(),
        width = ZImagePipeline.SIZE_PX,
        height = ZImagePipeline.SIZE_PX,
      )
    } finally {
      try {
        graphs.close()
      } catch (_: Throwable) {
      }
      System.gc()
    }
  }

  /** Flat embed rows re-chunked for [ZImagePipeline.rowsOf]. */
  private fun embedRows(embedFile: File, ids: IntArray): Array<FloatArray> {
    require(ids.isNotEmpty()) { "No token ids to embed" }
    val flat = ZImageEmbedLookup.gatherRows(embedFile, ids)
    val dim = ZImageHostLoop.EMBED_DIM
    return Array(ids.size) { r -> flat.copyOfRange(r * dim, (r + 1) * dim) }
  }

  private fun closeTextEncoder() {
    textEncoderInterpreter?.close()
    textEncoderInterpreter = null
  }
  private fun closeUnets() {
    unetMainInterpreters.forEach { it.close() }
    unetMainInterpreters = emptyList()
    unetFinalInterpreter?.close()
    unetFinalInterpreter = null
  }

  private fun closeVae() {
    vaeInterpreter?.close()
    vaeInterpreter = null
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
      // Keep thread count modest — each thread holds activation buffers.
      setNumThreads(2)
      // Diffusion graphs fail XNNPack reshape (node prepare errors). Force
      // the reference kernels; GPU is already off for OOM/JNI reasons.
      try {
        setUseXNNPACK(false)
      } catch (t: Throwable) {
        Log.w(TAG, "setUseXNNPACK(false) unavailable: ${t.message}")
      }
      if (tryGpuDelegate) {
        try {
          val delegate = GpuDelegate()
          addDelegate(delegate)
          gpuDelegates.add(delegate)
        } catch (t: Throwable) {
          tryGpuDelegate = false
          Log.w(TAG, "GPU delegate unavailable, using CPU: ${t.message}")
        }
      }
    }

    val modelFile = tfliteFiles.first()
    return Interpreter(modelFile, options)
  }

  /**
   * Phased load to cut peak RSS: encode → drop encoder → denoise → drop UNets →
   * VAE decode → unload. Still heavy, but avoids holding every graph at once
   * with a warm Gemma session.
   */
  fun generateImage(
    context: Context,
    config: GenerationConfig,
    onProgress: (String, Int) -> Unit = { _, _ -> },
    modelDirOverride: File? = null,
  ): PipelineResult {
    val modelDir = modelDirOverride ?: getModelDir(context, config.modelType)
    unloadModel()

    val spec = when (config.modelType) {
      ModelType.Z_IMAGE_TURBO -> ImageGenerationModels.MODEL_SPECS[ImageGenerationModels.MODEL_Z_IMAGE_TURBO]
      ModelType.FLUX_2_KLEIN -> ImageGenerationModels.MODEL_SPECS[ImageGenerationModels.MODEL_FLUX_2_KLEIN]
    } ?: throw IllegalStateException("No model spec for ${config.modelType}")

    val promptText = config.prompt.ifBlank { "A beautiful image" }

    // Z-Image Turbo: full host loop (pre-check → tokenize → embed lookup →
    // qwen_enc → DiT chunks → zvae). Graphs are 256 px-fixed; anything else
    // is clamped below. Returns ahead of the latent pre-allocation below,
    // which only the generic SD-style path consumes.
    if (config.modelType == ModelType.Z_IMAGE_TURBO) {
      return generateZImage(config, modelDir, promptText, onProgress)
    }

    onProgress("Preparing latents", 5)
    val latentHeight = config.size / spec.latentHeightFactor
    val latentWidth = config.size / spec.latentWidthFactor
    val latentChannels = spec.latentChannels

    val seed = config.seed ?: kotlin.random.Random.nextInt()
    val rng = kotlin.random.Random(seed)
    val latents = Array(latentHeight * latentWidth * latentChannels) {
      floatArrayOf((rng.nextFloat() - 0.5f) * 2f)
    }

    onProgress("Loading text encoder", 8)
    textEncoderInterpreter = createInterpreter(modelDir, spec.textEncoder)
    onProgress("Encoding prompt", 12)
    val textEmbeddings = encodePrompt(config.modelType, promptText)
    closeTextEncoder()
    System.gc()

    onProgress("Loading UNet", 15)
    unetMainInterpreters = spec.unetMain.map { fileName ->
      createInterpreter(modelDir, listOf(fileName))
    }
    unetFinalInterpreter = createInterpreter(modelDir, spec.unetFinal)
    loadedModelType = config.modelType

    val scheduler = DiffusionScheduler.createState()
    val timesteps = DiffusionScheduler.getTimestepsForInference(scheduler, config.steps)

    for ((stepIdx, timestep) in timesteps.withIndex()) {
      val progress = 18 + ((stepIdx + 1) * 65 / timesteps.size)
      onProgress("Denoising step ${stepIdx + 1}/${timesteps.size}", progress)

      val scaledLatents = scaleLatentsForTimestep(latents, timestep, scheduler)

      var noisePred: Array<FloatArray> = emptyArray()
      for ((blockIdx, interpreter) in unetMainInterpreters.withIndex()) {
        val blockInput = if (blockIdx == 0) scaledLatents else noisePred
        noisePred = runUnetBlock(
          interpreter,
          blockInput,
          textEmbeddings,
          timestep,
          latentHeight,
          latentWidth,
          latentChannels,
        )
      }

      val finalNoise = runUnetFinal(
        unetFinalInterpreter!!,
        noisePred,
        textEmbeddings,
        timestep,
        latentHeight,
        latentWidth,
        latentChannels,
      )

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

    closeUnets()
    System.gc()

    onProgress("Loading VAE", 88)
    vaeInterpreter = createInterpreter(modelDir, spec.vae)
    onProgress("Decoding image", 92)
    val imageBytes = decodeLatentsToPng(
      vaeInterpreter!!,
      latents,
      latentHeight,
      latentWidth,
      latentChannels,
      config.size,
    )
    closeVae()
    loadedModelType = null

    onProgress("Complete", 100)
    return PipelineResult(imageBytes = imageBytes, width = config.size, height = config.size)
  }

  private fun encodePrompt(
    modelType: ModelType,
    prompt: String,
  ): Array<FloatArray> {
    val encoder = textEncoderInterpreter ?: throw IllegalStateException("Text encoder not loaded")
    val inputShape = encoder.getInputTensor(0).shape()
    val outputShape = encoder.getOutputTensor(0).shape()
    Log.d(
      TAG,
      "encodePrompt($modelType) in=${inputShape.contentToString()} out=${outputShape.contentToString()}",
    )

    // Rank-3 float embeddings (Z-Image / modern encoders) cannot be filled
    // from UTF-8 bytes — that path triggers TFLite reduce/SUM prepare errors.
    if (inputShape.size >= 3) {
      throw IllegalStateException(
        "Text encoder expects rank-${inputShape.size} tensor " +
          "${inputShape.contentToString()} (precomputed embeddings), " +
          "but Nova only has a stub UTF-8 path. Host tokenization required.",
      )
    }

    val promptBytes = prompt.toByteArray(Charsets.UTF_8)

    val inputArray = when {
      inputShape.size == 2 && inputShape[1] == 1 -> {
        val seqLen = inputShape[0].coerceAtLeast(1)
        Array(seqLen) { floatArrayOf(promptBytes.getOrElse(it % promptBytes.size) { 0 }.toFloat()) }
      }
      inputShape.size == 2 && inputShape[1] > 1 -> {
        val seqLen = inputShape[0].coerceAtLeast(1)
        val dim = inputShape[1]
        Array(seqLen) { i ->
          val base = if (i < promptBytes.size) promptBytes[i].toFloat() else 0f
          FloatArray(dim) { j -> if (j == 0) base else 0f }
        }
      }
      else -> {
        val total = inputShape.fold(1) { a, b ->
          val dim = if (b <= 0) 1 else b
          a * dim
        }.coerceAtLeast(1)
        Array(total) { floatArrayOf(promptBytes.getOrElse(it % promptBytes.size) { 0 }.toFloat()) }
      }
    }

    val outRows = outputShape.getOrElse(0) { 1 }.coerceAtLeast(1)
    val outCols = if (outputShape.size >= 2) {
      outputShape[1].coerceAtLeast(1)
    } else {
      1
    }
    val outputArray = Array(outRows) { FloatArray(outCols) }
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
    val modelDirName = when (modelType) {
      ModelType.Z_IMAGE_TURBO -> ImageGenerationModels.MODEL_Z_IMAGE_TURBO
      ModelType.FLUX_2_KLEIN -> ImageGenerationModels.MODEL_FLUX_2_KLEIN
    }
    return resolveDiffusionModelDir(context, modelDirName)
  }

  /**
   * Flutter [path_provider] documents dir on Android is
   * `Context.getDir("flutter")` → `/data/.../app_flutter` (NOT `getDir("app_flutter")`,
   * which resolves to `app_app_flutter`).
   *
   * Prefer that path (where Dart downloads), then legacy / external fallbacks.
   */
  fun resolveDiffusionModelDir(context: Context, modelDirName: String): File {
    val candidates = diffusionModelDirCandidates(context, modelDirName)
    val matched = candidates.firstOrNull { dir -> hasTfliteWeights(dir) }
    if (matched != null) {
      Log.d(TAG, "Resolved diffusion model dir: ${matched.absolutePath}")
      return matched
    }
    Log.w(
      TAG,
      "No tflite weights for $modelDirName; searched: " +
        candidates.joinToString { it.absolutePath },
    )
    return candidates.first()
  }

  fun diffusionModelDirCandidates(context: Context, modelDirName: String): List<File> {
    return diffusionRootCandidates(context).map { root -> File(root, modelDirName) }
  }

  fun diffusionRootCandidates(context: Context): List<File> {
    // getDir("flutter") → .../app_flutter (Flutter path_provider documents).
    // getDir("app_flutter") → .../app_app_flutter (wrong; kept last for legacy).
    return listOfNotNull(
      File(context.getDir("flutter", Context.MODE_PRIVATE), "diffusion_models"),
      File(context.filesDir, "app_flutter/diffusion_models"),
      context.getExternalFilesDir(null)?.let { File(it, "diffusion_models") },
      File(context.filesDir, "diffusion_models"),
      File(context.getDir("app_flutter", Context.MODE_PRIVATE), "diffusion_models"),
    ).distinctBy { it.absolutePath }
  }

  fun hasTfliteWeights(dir: File): Boolean {
    return dir.exists() && dir.isDirectory &&
      dir.listFiles()?.any { file ->
        file.isFile && file.extension.equals("tflite", ignoreCase = true)
      } == true
  }
}
