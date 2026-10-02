package dev.nova.assistant

import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.sin

/**
 * Host-side tensor math for the Z-Image Turbo LiteRT graphs.
 *
 * Pure JVM (no Android imports) so every rule is unit-testable. Each constant
 * and formula here is traced from the published graphs or from the diffusers
 * reference; see `docs/z-image-turbo-litert.md` for the provenance of each.
 *
 * Latents are flat row-major `[channels][height][width]`. Patch tensors are
 * flat row-major `[numPatches][patchDim]`.
 */
object ZImageHostLoop {
  const val LATENT_CHANNELS = 16
  const val PATCH_SIZE = 2
  const val SEQ_MULTI_OF = 32
  const val CONTEXT_TOKENS = 32
  const val EMBED_SEQUENCE_TOKENS = 64
  const val EMBED_DIM = 2560
  const val MODEL_DIM = 3840
  const val TIME_SCALE = 1000f
  const val TIME_EMBED_DIM = 256
  const val TIME_EMBED_MID = 1024
  const val MAX_PERIOD = 10000f
  const val VAE_SCALING_FACTOR = 0.3611f
  const val VAE_SHIFT_FACTOR = 0.1159f

  private const val BASE_SEQ_LEN = 256
  private const val MAX_SEQ_LEN = 4096
  private const val BASE_SHIFT = 0.5f
  private const val MAX_SHIFT = 1.15f

  /**
   * Weights of `TimestepEmbedder`, row-major `[out, in]` to match the
   * `t_embedder.mlp.{0,2}.weight` tensors in the base checkpoint.
   */
  data class TimestepEmbedderWeights(
    val mlp0Weight: FloatArray,
    val mlp0Bias: FloatArray,
    val mlp2Weight: FloatArray,
    val mlp2Bias: FloatArray,
  ) {
    init {
      require(mlp0Weight.size == TIME_EMBED_MID * TIME_EMBED_DIM) {
        "mlp0Weight must be [1024,256], got ${mlp0Weight.size}"
      }
      require(mlp0Bias.size == TIME_EMBED_MID) { "mlp0Bias must be [1024]" }
      require(mlp2Weight.size == TIME_EMBED_DIM * TIME_EMBED_MID) {
        "mlp2Weight must be [256,1024], got ${mlp2Weight.size}"
      }
      require(mlp2Bias.size == TIME_EMBED_DIM) { "mlp2Bias must be [256]" }
    }
  }

  /** Padded context features plus the per-token pad mask from `_pad_with_ids`. */
  data class PaddedContext(
    val features: Array<FloatArray>,
    /** `true` marks a padding slot, matching `_pad_with_ids`' `pad_mask`. */
    val padMask: BooleanArray,
    val length: Int,
  ) {
    val realTokenCount: Int get() = padMask.count { !it }
  }

  // ---------------------------------------------------------------- patchify

  fun imageSeqLen(latentHeight: Int, latentWidth: Int): Int =
    (latentHeight / PATCH_SIZE) * (latentWidth / PATCH_SIZE)

  fun patchDim(channels: Int, patchSize: Int = PATCH_SIZE): Int =
    channels * patchSize * patchSize

  /**
   * `ZImageTransformer2DModel._patchify_image` with `F=1, pF=1`.
   *
   * The reference does `view(C, F_t, pF, H_t, pH, W_t, pW).permute(1,3,5,2,4,6,0)`,
   * which reduces to token `ht * gridW + wt` and within-patch
   * `(dy * patchSize + dx) * channels + c` — pixel-major, channel-minor.
   */
  fun patchify(
    latent: FloatArray,
    channels: Int,
    height: Int,
    width: Int,
    patchSize: Int = PATCH_SIZE,
  ): FloatArray {
    requireDivisible(height, patchSize, "latent height")
    requireDivisible(width, patchSize, "latent width")
    require(latent.size == channels * height * width) {
      "latent must be [channels][height][width] = ${channels * height * width}, got ${latent.size}"
    }
    val gridH = height / patchSize
    val gridW = width / patchSize
    val dim = patchDim(channels, patchSize)
    val plane = height * width
    val out = FloatArray(gridH * gridW * dim)
    for (ht in 0 until gridH) {
      for (wt in 0 until gridW) {
        val tokenBase = (ht * gridW + wt) * dim
        for (dy in 0 until patchSize) {
          val row = (ht * patchSize + dy) * width + wt * patchSize
          for (dx in 0 until patchSize) {
            val withinBase = (dy * patchSize + dx) * channels
            val pos = row + dx
            for (c in 0 until channels) {
              out[tokenBase + withinBase + c] = latent[c * plane + pos]
            }
          }
        }
      }
    }
    return out
  }

  /** Exact inverse of [patchify]. */
  fun unpatchify(
    patches: FloatArray,
    channels: Int,
    height: Int,
    width: Int,
    patchSize: Int = PATCH_SIZE,
  ): FloatArray {
    requireDivisible(height, patchSize, "latent height")
    requireDivisible(width, patchSize, "latent width")
    val gridH = height / patchSize
    val gridW = width / patchSize
    val dim = patchDim(channels, patchSize)
    val expected = gridH * gridW * dim
    require(patches.size == expected) { "patches must be $expected values, got ${patches.size}" }
    val plane = height * width
    val out = FloatArray(plane * channels)
    for (ht in 0 until gridH) {
      for (wt in 0 until gridW) {
        val tokenBase = (ht * gridW + wt) * dim
        for (dy in 0 until patchSize) {
          val row = (ht * patchSize + dy) * width + wt * patchSize
          for (dx in 0 until patchSize) {
            val withinBase = (dy * patchSize + dx) * channels
            val src = tokenBase + withinBase
            val pos = row + dx
            for (c in 0 until channels) {
              out[c * plane + pos] = patches[src + c]
            }
          }
        }
      }
    }
    return out
  }

  private fun requireDivisible(value: Int, divisor: Int, label: String) {
    require(value % divisor == 0) { "$label $value must be divisible by $divisor" }
  }

  // --------------------------------------------------------- context padding

  fun paddedContextLength(tokenCount: Int): Int =
    tokenCount + ((SEQ_MULTI_OF - tokenCount % SEQ_MULTI_OF) % SEQ_MULTI_OF)

  /**
   * `_pad_with_ids`: pad to a multiple of 32 by repeating the last row.
   *
   * The graphs hard-code 32 context tokens, so [maxTokens] truncates longer
   * prompts rather than growing the sequence. Pad positions are `(0,0,0)` and
   * the pad feature is the last real row; both are graph-internal, but the
   * repeated row is produced here.
   */
  fun padContext(
    features: Array<FloatArray>,
    dim: Int,
    maxTokens: Int = CONTEXT_TOKENS,
  ): PaddedContext {
    require(features.isNotEmpty()) { "context features must not be empty" }
    require(features.all { it.size == dim }) { "every context row must have $dim values" }
    val real = features.size.coerceAtMost(maxTokens)
    val total = paddedContextLength(real)
    val padded = Array(total) { FloatArray(dim) }
    val padMask = BooleanArray(total)
    val last = features[real - 1]
    for (i in 0 until total) {
      val source = if (i < real) features[i] else last
      source.copyInto(padded[i])
      padMask[i] = i >= real
    }
    return PaddedContext(padded, padMask, total)
  }

  /**
   * Left-pad `inputs_embeds` to the encoder's fixed sequence length.
   *
   * `qwen_enc` takes `[1,64,2560]` with no mask input and the encoder is
   * causal, so padding must go on the left; right padding would shift the real
   * tokens' positions.
   */
  fun leftPadEmbedSequence(rows: Array<FloatArray>, target: Int = EMBED_SEQUENCE_TOKENS): Array<FloatArray> {
    require(rows.size <= target) { "cannot pad $target from ${rows.size} rows" }
    val out = Array(target) { FloatArray(EMBED_DIM) }
    val offset = target - rows.size
    for (i in rows.indices) {
      rows[i].copyInto(out[offset + i])
    }
    return out
  }

  // ------------------------------------------------------- timestep embedder

  /** The value the transformer's `t_embedder` sees: `(1 - sigma) * t_scale`. */
  fun embedderInput(sigma: Float): Float = (1f - sigma) * TIME_SCALE

  /**
   * `TimestepEmbedder.timestep_embedding` with `max_period=10000`.
   *
   * `concat([cos(t * freqs), sin(t * freqs)])` — cos first, then sin — with
   * `freqs[i] = exp(-ln(max_period) * i / (dim / 2))`.
   */
  fun timestepEmbedding(t: Float, dim: Int = TIME_EMBED_DIM, maxPeriod: Float = MAX_PERIOD): FloatArray {
    val half = dim / 2
    val out = FloatArray(dim)
    for (i in 0 until half) {
      val freq = exp(-ln(maxPeriod) * i.toDouble() / half).toFloat()
      val arg = t * freq
      out[i] = cos(arg)
      out[half + i] = sin(arg)
    }
    return out
  }

  /** Stable `x * sigmoid(x)`. */
  fun silu(x: Float): Float {
    if (x >= 0f) return x / (1f + exp(-x))
    val ex = exp(x)
    return x * ex / (1f + ex)
  }

  /**
   * `pos[1,256]` for the given sigma: sinusoidal embedding, then
   * `Linear(256->1024) -> SiLU -> Linear(1024->256)`.
   */
  fun timestepEmbeddingForSigma(sigma: Float, weights: TimestepEmbedderWeights): FloatArray {
    val freq = timestepEmbedding(embedderInput(sigma))
    val hidden = FloatArray(TIME_EMBED_MID)
    for (i in 0 until TIME_EMBED_MID) {
      var acc = weights.mlp0Bias[i]
      val row = i * TIME_EMBED_DIM
      for (j in 0 until TIME_EMBED_DIM) {
        acc += freq[j] * weights.mlp0Weight[row + j]
      }
      hidden[i] = silu(acc)
    }
    val out = FloatArray(TIME_EMBED_DIM)
    for (k in 0 until TIME_EMBED_DIM) {
      var acc = weights.mlp2Bias[k]
      val row = k * TIME_EMBED_MID
      for (i in 0 until TIME_EMBED_MID) {
        acc += hidden[i] * weights.mlp2Weight[row + i]
      }
      out[k] = acc
    }
    return out
  }

  // ------------------------------------------------------------ sigma schedule

  /** `get_default_z_image_sigmas(n) = linspace(1.0, 1/n, n)`. */
  fun defaultSigmas(steps: Int): FloatArray {
    require(steps >= 1) { "steps must be >= 1" }
    if (steps == 1) return floatArrayOf(1f)
    val start = 1f
    val stop = 1f / steps
    val delta = (stop - start) / (steps - 1)
    return FloatArray(steps) { start + delta * it }
  }

  /**
   * `calculate_shift` from `pipeline_z_image.py`. At 256 px this yields 0.5.
   */
  fun calculateShift(seqLen: Int): Float {
    val m = (MAX_SHIFT - BASE_SHIFT) / (MAX_SEQ_LEN - BASE_SEQ_LEN)
    val b = BASE_SHIFT - m * BASE_SEQ_LEN
    return m * seqLen + b
  }

  /**
   * `FlowMatchEulerDiscreteScheduler._time_shift_exponential` with the
   * `sigma=1.0` argument used by `set_timesteps`.
   */
  fun timeShift(mu: Float, sigma: Float): Float {
    val e = exp(mu)
    val p = Math.pow((1.0 / sigma - 1.0).toDouble(), 1.0)
    return (e / (e + p)).toFloat()
  }

  /**
   * Full sigma schedule of `steps + 1` entries: resolution-shifted defaults plus
   * the terminal sigma of 0.0 that `set_timesteps` appends.
   */
  fun sigmaSchedule(steps: Int, seqLen: Int = imageSeqLen(32, 32)): FloatArray {
    val mu = calculateShift(seqLen)
    val base = defaultSigmas(steps)
    val out = FloatArray(steps + 1)
    for (i in 0 until steps) {
      out[i] = timeShift(mu, base[i])
    }
    out[steps] = 0f
    return out
  }

  // ------------------------------------------------------------ denoising math

  /**
   * `noise_pred = -(cond + guidance * (cond - uncond))`.
   *
   * The negation is applied after CFG, matching `pipeline_z_image.py`.
   */
  fun applyClassifierFreeGuidance(
    cond: FloatArray,
    uncond: FloatArray,
    guidance: Float,
  ): FloatArray {
    require(cond.size == uncond.size) { "branches must match, got ${cond.size} and ${uncond.size}" }
    val out = FloatArray(cond.size)
    for (i in cond.indices) {
      out[i] = -(cond[i] + guidance * (cond[i] - uncond[i]))
    }
    return out
  }

  /**
   * `FlowMatchEulerDiscreteScheduler.step`: `x += (sigmaNext - sigma) * v`.
   * Mutates [latent] in place and returns it.
   */
  fun eulerStep(
    latent: FloatArray,
    noisePred: FloatArray,
    sigma: Float,
    sigmaNext: Float,
  ): FloatArray {
    require(latent.size == noisePred.size) { "latent and noise must match" }
    val dt = sigmaNext - sigma
    for (i in latent.indices) {
      latent[i] += dt * noisePred[i]
    }
    return latent
  }

  /** `latents / scaling_factor + shift_factor` before `zvae`. */
  fun denormalizeLatents(latent: FloatArray): FloatArray =
    FloatArray(latent.size) { latent[it] / VAE_SCALING_FACTOR + VAE_SHIFT_FACTOR }

  // ------------------------------------------------------------------- decode

  /**
   * Pack `zvae`'s `[1,3,H,W]` output into ARGB_8888 pixels, row-major RGB.
   * Values are clamped to `[0,1]` and scaled to 8 bits.
   */
  fun chwToArgb(rgb: FloatArray, height: Int, width: Int): IntArray {
    val plane = height * width
    require(rgb.size >= 3 * plane) { "expected ${3 * plane} values, got ${rgb.size}" }
    val pixels = IntArray(plane)
    for (i in 0 until plane) {
      val r = to8Bit(rgb[i])
      val g = to8Bit(rgb[plane + i])
      val b = to8Bit(rgb[2 * plane + i])
      pixels[i] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
    }
    return pixels
  }

  private fun to8Bit(value: Float): Int = (value.coerceIn(0f, 1f) * 255f + 0.5f).toInt().coerceIn(0, 255)
}
