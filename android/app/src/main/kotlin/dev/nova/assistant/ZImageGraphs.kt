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
      toBuffer(values)
    }.toTypedArray()
    val outShape = interp.getOutputTensor(0).shape()
    require(interp.getOutputTensor(0).dataType() == DataType.FLOAT32) {
      "$graphName output must be FLOAT32"
    }
    val outCount = outShape.fold(1) { a, b -> a * b }
    val outBuffer = ByteBuffer.allocateDirect(outCount * 4).order(ByteOrder.nativeOrder())
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
    try {
      interpreters.remove(name)?.close()
    } catch (_: Throwable) {
    }
  }

  companion object {
    private fun toBuffer(values: FloatArray): ByteBuffer {
      val buffer = ByteBuffer.allocateDirect(values.size * 4).order(ByteOrder.nativeOrder())
      buffer.asFloatBuffer().put(values)
      buffer.rewind()
      return buffer
    }

    private fun defaultOpen(file: File): Interpreter {
      val options = Interpreter.Options().apply {
        setNumThreads(2)
        try {
          setUseXNNPACK(false)
        } catch (_: Throwable) {
        }
      }
      return Interpreter(file, options)
    }
  }
}
