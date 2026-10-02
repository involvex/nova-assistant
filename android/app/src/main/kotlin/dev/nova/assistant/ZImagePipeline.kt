package dev.nova.assistant

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

/**
 * End-to-end Z-Image Turbo orchestration at 256 px.
 *
 * Pure JVM (no Android imports): graph execution goes through [ZImageGraphs]
 * so the full path — tokenize → embed → `qwen_enc` → context → DiT loop
 * with CFG → `zvae` — runs in unit tests against fake graphs. Shapes follow
 * `docs/z-image-turbo-litert.md`; every I/O size is asserted by the graph
 * layer before the call.
 */
object ZImagePipeline {
  const val SIZE_PX = 256
  const val LATENT_HW = 32
  const val IMAGE_TOKENS = 256
  const val CONTEXT_TOKENS = 32
  const val UNIFIED_TOKENS = IMAGE_TOKENS + CONTEXT_TOKENS
  const val MAX_PROMPT_TOKENS = 32

  /** `x`/`mask` element counts from the verified signatures (all zeros). */
  const val X_IMG_SIZE = 256 * 64
  const val X_FULL_SIZE = UNIFIED_TOKENS * 64
  const val X_CTX_SIZE = CONTEXT_TOKENS * 64

  data class Request(
    val prompt: String,
    val uncondPrompt: String = "",
    val steps: Int,
    val guidance: Float,
    val seed: Long,
  )

  /**
   * Runs the full pipeline, returning RGB `[3,256,256]` CHW float32.
   * Callers convert with [ZImageHostLoop.chwToArgb]. Releases graph phases
   * as it goes (text → context → denoise → vae) to bound peak RSS.
   */
  fun generate(
    graphs: ZImageGraphs,
    tokenize: (String) -> IntArray,
    rowsOf: (IntArray) -> Array<FloatArray>,
    weights: ZImageHostLoop.TimestepEmbedderWeights,
    req: Request,
    onProgress: (String, Int) -> Unit = { _, _ -> },
  ): FloatArray {
    require(req.steps >= 1) { "steps must be >= 1" }

    onProgress("Encoding prompt", 8)
    val condCtx = branchContext(graphs, tokenize, rowsOf, req.prompt)
    // `do_classifier_free_guidance == guidance_scale > 0` in pipeline_z_image.py.
    // Z-Image Turbo ships guidance-distilled, so guidance 0 must run the DiT
    // once: the uncond pass is a second full sweep of all 6 908 MB blocks.
    val useCfg = req.guidance > 0f
    val uncondCtx = if (useCfg) branchContext(graphs, tokenize, rowsOf, req.uncondPrompt) else null
    graphs.releaseTextEncoder()
    graphs.releaseContextGraphs()

    onProgress("Preparing latents", 12)
    val latent = gaussianLatent(
      Random(req.seed),
      ZImageHostLoop.LATENT_CHANNELS * LATENT_HW * LATENT_HW,
    )
    val sigmas = ZImageHostLoop.sigmaSchedule(req.steps, IMAGE_TOKENS)

    for (step in 0 until req.steps) {
      onProgress(
        "Denoising step ${step + 1}/${req.steps}",
        15 + ((step + 1) * 65 / req.steps),
      )
      val sigma = sigmas[step]
      val sigmaNext = sigmas[step + 1]
      val pos = ZImageHostLoop.timestepEmbeddingForSigma(sigma, weights)
      val condNoise = denoiseBranch(graphs, latent, condCtx, pos)
      // With CFG off the only negation is the pipeline's unconditional
      // `noise_pred = -noise_pred`, which applyClassifierFreeGuidance
      // already folds in at guidance 0.
      val guided = if (useCfg) {
        val uncondNoise = denoiseBranch(graphs, latent, checkNotNull(uncondCtx), pos)
        ZImageHostLoop.applyClassifierFreeGuidance(condNoise, uncondNoise, req.guidance)
      } else {
        ZImageHostLoop.applyClassifierFreeGuidance(condNoise, condNoise, 0f)
      }
      ZImageHostLoop.eulerStep(latent, guided, sigma, sigmaNext)
    }
    graphs.releaseDenoiseGraphs()

    onProgress("Decoding image", 92)
    val denorm = ZImageHostLoop.denormalizeLatents(latent)
    val rgb = graphs.vae(denorm)
    graphs.releaseVae()
    require(rgb.size == 3 * SIZE_PX * SIZE_PX) {
      "vae must return [3,256,256], got ${rgb.size} values"
    }
    onProgress("Complete", 100)
    return rgb
  }

  /**
   * One text branch: ids → left-padded embeds → `qwen_enc` → first n real
   * rows (n ≤ 32) → repeat-last-row pad to 32 → `z_embc` → `z_refc`.
   */
  fun branchContext(
    graphs: ZImageGraphs,
    tokenize: (String) -> IntArray,
    rowsOf: (IntArray) -> Array<FloatArray>,
    prompt: String,
  ): FloatArray {
    val ids = tokenize(prompt).take(MAX_PROMPT_TOKENS).toIntArray()
    // Empty prompts (the CFG uncond branch) encode as all-zero embeds.
    val inRows: Array<FloatArray> = if (ids.isEmpty()) {
      arrayOf(FloatArray(ZImageHostLoop.EMBED_DIM))
    } else {
      val rows = rowsOf(ids)
      require(rows.size == ids.size) {
        "rowsOf must return one row per id, got ${rows.size} for ${ids.size}"
      }
      rows
    }
    val paddedIn = flatten(leftPadTo(inRows, ZImageHostLoop.EMBED_SEQUENCE_TOKENS))
    val capFeats = graphs.qwenEnc(paddedIn)
    require(capFeats.size == ZImageHostLoop.EMBED_SEQUENCE_TOKENS * ZImageHostLoop.EMBED_DIM) {
      "qwen_enc must return [64,2560], got ${capFeats.size} values"
    }
    // Inputs were left-padded, so the real rows are the LAST ids.size rows;
    // "first n real rows" are the head of that tail (n ≤ 32).
    val real = ids.size.coerceAtMost(CONTEXT_TOKENS)
    val firstReal = rowsOfRange(
      capFeats,
      offsetRows = ZImageHostLoop.EMBED_SEQUENCE_TOKENS - ids.size,
      count = real,
    )
    val padded = ZImageHostLoop.padContext(
      if (firstReal.isEmpty()) arrayOf(FloatArray(ZImageHostLoop.EMBED_DIM)) else firstReal,
      ZImageHostLoop.EMBED_DIM,
      CONTEXT_TOKENS,
    )
    require(padded.features.size == CONTEXT_TOKENS) {
      "context must be $CONTEXT_TOKENS rows, got ${padded.features.size}"
    }
    val embc = graphs.embc(flatten(padded.features))
    val x = FloatArray(X_CTX_SIZE)
    val mask = FloatArray(X_CTX_SIZE)
    return graphs.refc(embc, x, mask)
  }

  /** One DiT pass for a branch at the current sigma → velocity `[16,32,32]`. */
  fun denoiseBranch(
    graphs: ZImageGraphs,
    latent: FloatArray,
    ctx: FloatArray,
    pos: FloatArray,
  ): FloatArray {
    require(ctx.size == CONTEXT_TOKENS * ZImageHostLoop.MODEL_DIM) {
      "ctx must be [32,3840], got ${ctx.size} values"
    }
    val img = ZImageHostLoop.patchify(
      latent,
      ZImageHostLoop.LATENT_CHANNELS,
      LATENT_HW,
      LATENT_HW,
    )
    val imgT = graphs.embx(img)
    val imgR = graphs.refx(imgT, FloatArray(X_IMG_SIZE), FloatArray(X_IMG_SIZE), pos)
    var hidden = concatRows(imgR, IMAGE_TOKENS, ctx, CONTEXT_TOKENS, ZImageHostLoop.MODEL_DIM)
    val x = FloatArray(X_FULL_SIZE)
    val mask = FloatArray(X_FULL_SIZE)
    for (block in 0..5) {
      hidden = graphs.mainBlock(block, hidden, x, mask, pos)
    }
    val velocity = graphs.final(hidden, pos)
    require(velocity.size == UNIFIED_TOKENS * ZImageHostLoop.patchDim(ZImageHostLoop.LATENT_CHANNELS)) {
      "final must return [288,64], got ${velocity.size} values"
    }
    // Row-major concat put image tokens first: only those unpatchify.
    // Context rows carry no pixels and are dropped here.
    val imageVelocity = velocity.copyOfRange(
      0,
      IMAGE_TOKENS * ZImageHostLoop.patchDim(ZImageHostLoop.LATENT_CHANNELS),
    )
    return ZImageHostLoop.unpatchify(
      imageVelocity,
      ZImageHostLoop.LATENT_CHANNELS,
      LATENT_HW,
      LATENT_HW,
    )
  }

  // ---------------------------------------------------------------- helpers

  /** Rows [offsetRows, offsetRows + count) of a flat row-major matrix. */
  fun rowsOfRange(feats: FloatArray, offsetRows: Int, count: Int): Array<FloatArray> {
    val dim = ZImageHostLoop.EMBED_DIM
    require(offsetRows >= 0 && count >= 0 && (offsetRows + count) * dim <= feats.size) {
      "rowsOfRange($offsetRows, $count) out of bounds for ${feats.size} values"
    }
    return Array(count) { r -> feats.copyOfRange((offsetRows + r) * dim, (offsetRows + r + 1) * dim) }
  }

  private fun leftPadTo(rows: Array<FloatArray>, target: Int): Array<FloatArray> {
    if (rows.size >= target) return rows.copyOfRange(0, target)
    val out = Array(target) { FloatArray(ZImageHostLoop.EMBED_DIM) }
    val offset = target - rows.size
    for (i in rows.indices) rows[i].copyInto(out[offset + i])
    return out
  }

  private fun flatten(rows: Array<FloatArray>): FloatArray {
    val dim = rows.firstOrNull()?.size ?: 0
    val out = FloatArray(rows.size * dim)
    for (i in rows.indices) rows[i].copyInto(out, i * dim)
    return out
  }

  private fun concatRows(
    first: FloatArray,
    firstRows: Int,
    second: FloatArray,
    secondRows: Int,
    dim: Int,
  ): FloatArray {
    require(first.size == firstRows * dim) { "first must be [$firstRows,$dim]" }
    require(second.size == secondRows * dim) { "second must be [$secondRows,$dim]" }
    val out = FloatArray((firstRows + secondRows) * dim)
    first.copyInto(out, 0)
    second.copyInto(out, first.size)
    return out
  }

  /** Seeded standard-normal latent via Box-Muller. */
  fun gaussianLatent(random: Random, size: Int): FloatArray {
    require(size > 0) { "latent size must be > 0" }
    val out = FloatArray(size)
    var i = 0
    while (i < size) {
      var u1 = random.nextFloat()
      val u2 = random.nextFloat()
      if (u1 <= 0f) u1 = Float.MIN_VALUE
      val radius = sqrt(-2.0 * ln(u1.toDouble()))
      val theta = 2.0 * PI * u2
      out[i++] = (radius * cos(theta)).toFloat()
      if (i < size) out[i++] = (radius * sin(theta)).toFloat()
    }
    return out
  }
}
