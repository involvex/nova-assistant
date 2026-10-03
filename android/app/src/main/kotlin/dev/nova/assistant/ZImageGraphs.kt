package dev.nova.assistant

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.tensorflow.lite.DataType
import org.tensorflow.lite.Interpreter

/**
 * Executable Z-Image graphs behind a seam the pipeline can test without
 * weights. All tensors are flat row-major float32 arrays; shapes follow
 * `docs/z-image-turbo-litert.md` (256 px fixed).
 *
 * Release methods bound peak RSS: the text encoder (3.5 GB), context graphs,
 * denoise graphs (6 x 908 MB files, mmap'd) and VAE are never held together.
 */
interface ZImageGraphs : AutoCloseable {
  /** `qwen_enc`: `[64,2560]` in → `[64,2560]` cap feats out. */
  fun qwenEnc(embeds: FloatArray): FloatArray

  /** `z_embx`: `[256,64]` patches in → `[256,3840]` out. */
  fun embx(img: FloatArray): FloatArray

  /** `z_refx`: image branch refiner → `[256,3840]`. */
  fun refx(cap: FloatArray, x: FloatArray, mask: FloatArray, pos: FloatArray): FloatArray

  /** `z_embc`: `[32,2560]` context in → `[32,3840]` out. */
  fun embc(cap: FloatArray): FloatArray

  /** `z_refc`: context refiner (no `pos` input) → `[32,3840]`. */
  fun refc(cap: FloatArray, x: FloatArray, mask: FloatArray): FloatArray

  /** `zc_main{index}`: `[288,3840]` hidden in → same shape out. */
  fun mainBlock(index: Int, hidden: FloatArray, x: FloatArray, mask: FloatArray, pos: FloatArray): FloatArray

  /** `zc_final`: `[288,3840]` hidden in → `[288,64]` velocity out. */
  fun final(hidden: FloatArray, pos: FloatArray): FloatArray

  /** `zvae`: denormalized latent `[16,32,32]` CHW in → RGB `[3,256,256]` CHW out. */
  fun vae(latentChw: FloatArray): FloatArray

  fun releaseTextEncoder()
  fun releaseContextGraphs()
  fun releaseDenoiseGraphs()
  fun releaseVae()
}

/**
 * [ZImageGraphs] over real `.tflite` files. Interpreters open lazily per
 * phase; every input is checked against the runtime tensor shape before the
 * call so a converted-graph layout drift fails with a named mismatch instead
 * of a native abort deep in a multi-minute run.
 */
class ZImageTfliteGraphs(
  private val modelDir: File,
  private val open: (File) -> Interpreter = { file -> defaultOpen(file) },
) : ZImageGraphs {
  private val interpreters = HashMap<String, Interpreter>()

  /**
   * Direct [ByteBuffer] pool keyed by `"<graph>#in<slot>"` / `"<graph>#out0"`.
   *
   * `runForMultipleInputsOutputs` requires direct buffers, and this model's
   * tensors are large: a 908 MB block takes 4 x 4.4 MB inputs plus a 4.4 MB
   * output *per call*, and a run is 6 blocks + `z_refx` + `z_embx` + `zc_final`
   * per step across 8 steps. Allocating fresh direct buffers every call leaves
   * hundreds of MB uncollected — direct memory is only reclaimed on GC — which
   * is what pushed PSS past MIUI's 6 GB third-party cap and got the process
   * killed mid-generation. One buffer per slot keeps the working set flat.
   */
  private val pooled = HashMap<String, ByteBuffer>()

  private fun pooledBuffer(key: String, floats: Int): ByteBuffer {
    val need = floats * 4
    val cached = pooled[key]
    if (cached != null && cached.capacity() >= need) {
      cached.clear()
      return cached
    }
    val fresh = ByteBuffer.allocateDirect(need).order(ByteOrder.nativeOrder())
    pooled[key] = fresh
    return fresh
  }

  private fun get(name: String): Interpreter {
    return interpreters.getOrPut(name) {
      val file = File(modelDir, name)
      require(file.isFile) { "Missing graph file: ${file.absolutePath}" }
      open(file)
    }
  }

  private fun runGraph(
    graphName: String,
    inputs: List<FloatArray>,
    docShapes: List<String>,
  ): FloatArray {
    val interp = get(graphName)
    require(interp.inputTensorCount == inputs.size) {
      "$graphName: expected ${inputs.size} inputs $docShapes, " +
        "graph takes ${interp.inputTensorCount}"
    }
    val buffers = inputs.mapIndexed { i, values ->
      val shape = interp.getInputTensor(i).shape()
      val want = shape.fold(1) { a, b -> a * b }
      require(values.size == want) {
        "$graphName input $i: got ${values.size} values, " +
          "graph wants ${shape.contentToString()} ($want)"
      }
      require(interp.getInputTensor(i).dataType() == DataType.FLOAT32) {
        "$graphName input $i must be FLOAT32"
      }
      val buffer = pooledBuffer("$graphName#in$i", want)
      buffer.asFloatBuffer().put(values)
      buffer.rewind()
      buffer
    }.toTypedArray()
    val outShape = interp.getOutputTensor(0).shape()
    require(interp.getOutputTensor(0).dataType() == DataType.FLOAT32) {
      "$graphName output must be FLOAT32"
    }
    val outCount = outShape.fold(1) { a, b -> a * b }
    val outBuffer = pooledBuffer("$graphName#out0", outCount)
    interp.runForMultipleInputsOutputs(buffers, mapOf(0 to outBuffer))
    outBuffer.rewind()
    val out = FloatArray(outCount)
    outBuffer.asFloatBuffer().get(out)
    return out
  }

  override fun qwenEnc(embeds: FloatArray): FloatArray =
    runGraph("qwen_enc.tflite", listOf(embeds), listOf("[1,64,2560]"))

  override fun embx(img: FloatArray): FloatArray =
    runGraph("z_embx.tflite", listOf(img), listOf("[1,256,64]"))

  override fun refx(cap: FloatArray, x: FloatArray, mask: FloatArray, pos: FloatArray): FloatArray =
    runGraph("z_refx.tflite", listOf(cap, x, mask, pos), listOf("[1,256,3840]", "[1,1,256,64]", "[1,1,256,64]", "[1,256]"))

  override fun embc(cap: FloatArray): FloatArray =
    runGraph("z_embc.tflite", listOf(cap), listOf("[1,32,2560]"))

  override fun refc(cap: FloatArray, x: FloatArray, mask: FloatArray): FloatArray =
    runGraph("z_refc.tflite", listOf(cap, x, mask), listOf("[1,32,3840]", "[1,1,32,64]", "[1,1,32,64]"))

  override fun mainBlock(index: Int, hidden: FloatArray, x: FloatArray, mask: FloatArray, pos: FloatArray): FloatArray {
    require(index in 0..5) { "main block index must be 0..5, got $index" }
    return runGraph(
      "zc_main$index.tflite",
      listOf(hidden, x, mask, pos),
      listOf("[1,288,3840]", "[1,1,288,64]", "[1,1,288,64]", "[1,256]"),
    )
  }

  override fun final(hidden: FloatArray, pos: FloatArray): FloatArray =
    runGraph("zc_final.tflite", listOf(hidden, pos), listOf("[1,288,3840]", "[1,256]"))

  override fun vae(latentChw: FloatArray): FloatArray =
    runGraph("zvae.tflite", listOf(latentChw), listOf("[1,16,32,32]"))

  override fun releaseTextEncoder() = release("qwen_enc.tflite")

  override fun releaseContextGraphs() {
    release("z_embc.tflite")
    release("z_refc.tflite")
  }

  override fun releaseDenoiseGraphs() {
    release("z_embx.tflite")
    release("z_refx.tflite")
    for (i in 0..5) release("zc_main$i.tflite")
    release("zc_final.tflite")
  }

  override fun releaseVae() = release("zvae.tflite")

  override fun close() {
    val names = interpreters.keys.toList()
    for (name in names) release(name)
  }

  private fun release(name: String) {
    // Direct buffers are GC-managed but not promptly reclaimed, so drop the
    // slots alongside the interpreter instead of waiting on a collection.
    pooled.keys.filter { it.startsWith("$name#") }.forEach { pooled.remove(it) }
    try {
      interpreters.remove(name)?.close()
    } catch (_: Throwable) {
    }
  }

  companion object {
    private fun defaultOpen(file: File): Interpreter {
      val options = Interpreter.Options().apply {
        // Leave one core for the UI thread; the denoise sweep is compute-bound
        // so this is the single biggest lever on generation wall time.
        val cores = Runtime.getRuntime().availableProcessors().coerceAtLeast(1)
        setNumThreads((cores - 1).coerceIn(2, 6))
        try {
          setUseXNNPACK(false)
        } catch (_: Throwable) {
        }
      }
      return Interpreter(file, options)
    }
  }
}
