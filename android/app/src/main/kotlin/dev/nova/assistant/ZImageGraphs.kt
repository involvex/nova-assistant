package dev.nova.assistant

import android.content.Context
import android.util.Log
import com.google.ai.edge.litert.Accelerator
import com.google.ai.edge.litert.CompiledModel
import com.google.ai.edge.litert.Environment
import java.io.File

/**
 * Executable Z-Image graphs behind a seam the pipeline can test without
 * weights. All tensors are flat row-major float32 arrays; shapes follow
 * `docs/z-image-turbo-litert.md` (256 px fixed).
 *
 * Release methods bound peak RSS: the text encoder (3.5 GB), context graphs,
 * denoise graphs and VAE are never held together. DiT main chunks additionally
 * use single-graph residency (only one `zc_main*` open at a time).
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

  /**
   * Drop embx/refx before the DiT main loop. Their outputs are already in
   * host tensors; keeping the GPU graphs resident while compiling `zc_main*`
   * pushed MIUI LMK over ~5 GB RSS.
   */
  fun releaseImageEmbedGraphs() {}
}

/**
 * [ZImageGraphs] over real `.tflite` files via LiteRT [CompiledModel].
 *
 * Upstream peak footprint is **one** sub-1 GB graph at a time. Caching all six
 * `zc_main*` (~908 MB each) + embx/refx on GPU FP32 got the process LMK'd
 * (`Kill 'dev.nova.assistant' ... to free 5151604kB rss`). This implementation:
 * - shares one [Environment] with compiler cache (re-open after release is cheap)
 * - keeps only one `zc_main*` resident
 * - releases embx/refx before the main loop
 * - prefers GPU FP32, falls back to CPU on compile failure
 */
class ZImageTfliteGraphs(
  private val modelDir: File,
  context: Context? = null,
) : ZImageGraphs {
  private val models = HashMap<String, CompiledModel>()
  private val accelerators = HashMap<String, Accelerator>()
  private val env: Environment = if (context != null) {
    // Compiler cache: sequential residency re-opens mains every step; without
    // a cache each 908 MB GPU compile costs ~40s on device.
    Environment.create(context, enableCompilerCache = true)
  } else {
    Environment.create()
  }

  private fun get(name: String): CompiledModel {
    return models.getOrPut(name) {
      val file = File(modelDir, name)
      require(file.isFile) { "Missing graph file: ${file.absolutePath}" }
      openCompiled(file, name)
    }
  }

  private fun openCompiled(file: File, name: String): CompiledModel {
    val preferCpu = name in CPU_PREFERRED
    if (!preferCpu) {
      try {
        val model = CompiledModel.create(file.absolutePath, gpuFp32Options(), env)
        accelerators[name] = Accelerator.GPU
        Log.i(TAG, "Compiled $name on GPU FP32 (resident=${models.size + 1})")
        return model
      } catch (t: Throwable) {
        Log.w(TAG, "GPU compile failed for $name, falling back to CPU: ${t.message}")
      }
    }
    val model = CompiledModel.create(file.absolutePath, CompiledModel.Options(Accelerator.CPU), env)
    accelerators[name] = Accelerator.CPU
    Log.i(
      TAG,
      "Compiled $name on CPU" +
        if (preferCpu) " (preferred)" else " (fallback)" +
        " (resident=${models.size + 1})",
    )
    return model
  }

  private fun runGraph(
    graphName: String,
    inputs: List<FloatArray>,
    docShapes: List<String>,
  ): FloatArray {
    val model = get(graphName)
    val ins = model.createInputBuffers()
    val outs = model.createOutputBuffers()
    try {
      require(ins.size == inputs.size) {
        "$graphName: expected ${inputs.size} inputs $docShapes, " +
          "graph takes ${ins.size}"
      }
      inputs.forEachIndexed { i, values ->
        try {
          ins[i].writeFloat(values)
        } catch (t: Throwable) {
          throw IllegalArgumentException(
            "$graphName input $i: writeFloat(${values.size}) failed " +
              "(doc shape ${docShapes.getOrNull(i)}): ${t.message}",
            t,
          )
        }
      }
      model.run(ins, outs)
      return outs[0].readFloat()
    } finally {
      ins.forEach { buf ->
        try {
          buf.close()
        } catch (_: Throwable) {
        }
      }
      outs.forEach { buf ->
        try {
          buf.close()
        } catch (_: Throwable) {
        }
      }
    }
  }

  override fun qwenEnc(embeds: FloatArray): FloatArray =
    runGraph("qwen_enc.tflite", listOf(embeds), listOf("[1,64,2560]"))

  override fun embx(img: FloatArray): FloatArray =
    runGraph("z_embx.tflite", listOf(img), listOf("[1,256,64]"))

  override fun refx(cap: FloatArray, x: FloatArray, mask: FloatArray, pos: FloatArray): FloatArray =
    runGraph(
      "z_refx.tflite",
      listOf(cap, x, mask, pos),
      listOf("[1,256,3840]", "[1,1,256,64]", "[1,1,256,64]", "[1,256]"),
    )

  override fun embc(cap: FloatArray): FloatArray =
    runGraph("z_embc.tflite", listOf(cap), listOf("[1,32,2560]"))

  override fun refc(cap: FloatArray, x: FloatArray, mask: FloatArray): FloatArray =
    runGraph(
      "z_refc.tflite",
      listOf(cap, x, mask),
      listOf("[1,32,3840]", "[1,1,32,64]", "[1,1,32,64]"),
    )

  override fun mainBlock(
    index: Int,
    hidden: FloatArray,
    x: FloatArray,
    mask: FloatArray,
    pos: FloatArray,
  ): FloatArray {
    require(index in 0..5) { "main block index must be 0..5, got $index" }
    // Single-graph residency: drop every other DiT chunk before compiling this
    // one. Upstream peak = one ~908 MB graph; holding 6× got LMK'd at 5.1 GB.
    for (i in 0..5) {
      if (i != index) release("zc_main$i.tflite")
    }
    if (index == 0) {
      // embx/refx outputs already live in [hidden]'s image rows after concat.
      releaseImageEmbedGraphs()
    }
    return runGraph(
      "zc_main$index.tflite",
      listOf(hidden, x, mask, pos),
      listOf("[1,288,3840]", "[1,1,288,64]", "[1,1,288,64]", "[1,256]"),
    )
  }

  override fun final(hidden: FloatArray, pos: FloatArray): FloatArray {
    // Drop the last main chunk before the tiny final head.
    for (i in 0..5) release("zc_main$i.tflite")
    return runGraph("zc_final.tflite", listOf(hidden, pos), listOf("[1,288,3840]", "[1,256]"))
  }

  override fun vae(latentChw: FloatArray): FloatArray =
    runGraph("zvae.tflite", listOf(latentChw), listOf("[1,16,32,32]"))

  override fun releaseTextEncoder() = release("qwen_enc.tflite")

  override fun releaseContextGraphs() {
    release("z_embc.tflite")
    release("z_refc.tflite")
  }

  override fun releaseImageEmbedGraphs() {
    release("z_embx.tflite")
    release("z_refx.tflite")
  }

  override fun releaseDenoiseGraphs() {
    releaseImageEmbedGraphs()
    for (i in 0..5) release("zc_main$i.tflite")
    release("zc_final.tflite")
  }

  override fun releaseVae() = release("zvae.tflite")

  override fun close() {
    val names = models.keys.toList()
    for (name in names) release(name)
    try {
      env.close()
    } catch (_: Throwable) {
    }
  }

  /** Which accelerator each open graph is running on (for logcat triage). */
  fun acceleratorOf(name: String): Accelerator? = accelerators[name]

  private fun release(name: String) {
    val closed = models.remove(name)
    if (closed != null) {
      try {
        closed.close()
      } catch (_: Throwable) {
      }
      Log.d(TAG, "Released $name (resident=${models.size})")
    }
    accelerators.remove(name)
  }

  companion object {
    private const val TAG = "ZImageTfliteGraphs"

    /**
     * Prefer CPU: upstream Pixel 8a table shows these faster on CPU, and
     * `zvae` fails classic TFLite OpenCL. Skip the GPU compile attempt.
     */
    private val CPU_PREFERRED = setOf(
      "zvae.tflite",
      "z_embc.tflite",
      "zc_final.tflite",
    )

    private fun gpuFp32Options(): CompiledModel.Options {
      return CompiledModel.Options(Accelerator.GPU).apply {
        gpuOptions = CompiledModel.GpuOptions(
          precision = CompiledModel.GpuOptions.Precision.FP32,
        )
      }
    }
  }
}
