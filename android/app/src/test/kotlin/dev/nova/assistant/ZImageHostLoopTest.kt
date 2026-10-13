package dev.nova.assistant

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.cos
import kotlin.math.sin

/**
 * Verifies the Z-Image Turbo host-loop math against hand-computed values taken
 * from the diffusers reference. See `docs/z-image-turbo-litert.md`.
 */
class ZImageHostLoopTest {
  private val delta = 1e-5f

  // ---------------------------------------------------------------- patchify

  @Test
  fun `patchify uses pixel-major channel-minor ordering`() {
    // channels=2, 4x4 latent, 2x2 patches -> 2x2 grid of 8-value patches.
    // latent[c][h][w] == c*16 + h*4 + w
    val channels = 2
    val height = 4
    val width = 4
    val latent = FloatArray(channels * height * width) { it.toFloat() }

    val patches = ZImageHostLoop.patchify(latent, channels, height, width)

    assertEquals(4 * 8, patches.size)
    val expected = floatArrayOf(
      // token 0: ht=0, wt=0
      0f, 16f, 1f, 17f, 4f, 20f, 5f, 21f,
      // token 1: ht=0, wt=1
      2f, 18f, 3f, 19f, 6f, 22f, 7f, 23f,
      // token 2: ht=1, wt=0
      8f, 24f, 9f, 25f, 12f, 28f, 13f, 29f,
      // token 3: ht=1, wt=1
      10f, 26f, 11f, 27f, 14f, 30f, 15f, 31f,
    )
    assertArrayEquals(expected, patches, 0f)
  }

  @Test
  fun `unpatchify is the exact inverse of patchify`() {
    val channels = 16
    val height = 32
    val width = 32
    val latent = FloatArray(channels * height * width) { (it % 251) / 7f }
    val patches = ZImageHostLoop.patchify(latent, channels, height, width)
    val restored = ZImageHostLoop.unpatchify(patches, channels, height, width)
    assertArrayEquals(latent, restored, 0f)
  }

  @Test
  fun `patch shapes match the published z_embx input`() {
    // 32x32 latent, 16 channels, 2x2 patches -> 256 tokens x 64 values.
    assertEquals(256, ZImageHostLoop.imageSeqLen(32, 32))
    assertEquals(64, ZImageHostLoop.patchDim(ZImageHostLoop.LATENT_CHANNELS))
    val patches = ZImageHostLoop.patchify(
      FloatArray(16 * 32 * 32),
      ZImageHostLoop.LATENT_CHANNELS,
      32,
      32,
    )
    assertEquals(256 * 64, patches.size)
  }

  @Test(expected = IllegalArgumentException::class)
  fun `patchify rejects a latent height that is not divisible by the patch size`() {
    ZImageHostLoop.patchify(FloatArray(2 * 3 * 4), 2, 3, 4)
  }

  // --------------------------------------------------------- context padding

  @Test
  fun `context length rounds up to a multiple of 32`() {
    assertEquals(32, ZImageHostLoop.paddedContextLength(1))
    assertEquals(32, ZImageHostLoop.paddedContextLength(31))
    assertEquals(32, ZImageHostLoop.paddedContextLength(32))
    assertEquals(64, ZImageHostLoop.paddedContextLength(33))
  }

  @Test
  fun `context padding repeats the last real row when padToken is null`() {
    val features = Array(3) { i -> FloatArray(2) { i * 2f + it } }
    val padded = ZImageHostLoop.padContext(features, dim = 2)

    assertEquals(32, padded.length)
    assertEquals(3, padded.realTokenCount)
    assertArrayEquals(floatArrayOf(0f, 1f), padded.features[0], 0f)
    assertArrayEquals(floatArrayOf(4f, 5f), padded.features[2], 0f)
    for (i in 3 until 32) {
      assertArrayEquals(floatArrayOf(4f, 5f), padded.features[i], 0f)
    }
    assertFalse(padded.padMask[2])
    assertTrue(padded.padMask[3])
    assertTrue(padded.padMask[31])
  }

  @Test
  fun `context padding uses learned padToken when provided`() {
    val features = Array(2) { i -> FloatArray(3) { (i + 1).toFloat() } }
    val token = floatArrayOf(9f, 8f, 7f)
    val padded = ZImageHostLoop.padContext(features, dim = 3, padToken = token)
    assertArrayEquals(floatArrayOf(1f, 1f, 1f), padded.features[0], 0f)
    for (i in 2 until 32) {
      assertArrayEquals(token, padded.features[i], 0f)
    }
  }

  @Test
  fun `applyLearnedPad overwrites only pad rows`() {
    val dim = 4
    val flat = FloatArray(3 * dim) { it.toFloat() }
    val token = floatArrayOf(100f, 101f, 102f, 103f)
    val out = ZImageHostLoop.applyLearnedPad(flat, rows = 3, dim = dim, realRows = 1, padToken = token)
    assertArrayEquals(floatArrayOf(0f, 1f, 2f, 3f), out.copyOfRange(0, 4), 0f)
    assertArrayEquals(token, out.copyOfRange(4, 8), 0f)
    assertArrayEquals(token, out.copyOfRange(8, 12), 0f)
    // Input unchanged.
    assertEquals(4f, flat[4], 0f)
  }

  @Test
  fun `context padding truncates prompts longer than the graph supports`() {
    val features = Array(48) { i -> floatArrayOf(i.toFloat()) }
    val padded = ZImageHostLoop.padContext(features, dim = 1, maxTokens = 32)
    assertEquals(32, padded.length)
    assertEquals(32, padded.realTokenCount)
    assertTrue(padded.padMask.none { it })
  }

  @Test
  fun `a full 32-token context is not padded`() {
    val features = Array(32) { i -> floatArrayOf(i.toFloat()) }
    val padded = ZImageHostLoop.padContext(features, dim = 1)
    assertEquals(32, padded.length)
    assertTrue(padded.padMask.none { it })
  }

  @Test
  fun `embed sequence is left padded so real tokens keep their positions`() {
    val rows = Array(2) { i -> FloatArray(ZImageHostLoop.EMBED_DIM) { (i * 100 + it).toFloat() } }
    val padded = ZImageHostLoop.leftPadEmbedSequence(rows, target = 5)

    assertEquals(5, padded.size)
    for (i in 0 until 3) {
      assertArrayEquals(FloatArray(ZImageHostLoop.EMBED_DIM), padded[i], 0f)
    }
    assertArrayEquals(rows[0], padded[3], 0f)
    assertArrayEquals(rows[1], padded[4], 0f)
  }

  // ------------------------------------------------------- timestep embedder

  @Test
  fun `timestep embedding lays out cos then sin with exponentially spaced freqs`() {
    val dim = 4
    val half = 2
    val t = 0.37f
    val emb = ZImageHostLoop.timestepEmbedding(t, dim = dim)

    val freq0 = 1.0f
    val freq1 = Math.exp(-Math.log(10000.0) * 1.0 / half).toFloat()

    assertEquals(cos(t * freq0), emb[0], delta)
    assertEquals(cos(t * freq1), emb[1], delta)
    assertEquals(sin(t * freq0), emb[2], delta)
    assertEquals(sin(t * freq1), emb[3], delta)
  }

  @Test
  fun `timestep embedding at t=0 is cos-only`() {
    val emb = ZImageHostLoop.timestepEmbedding(0f, dim = 4)
    assertEquals(1f, emb[0], delta)
    assertEquals(1f, emb[1], delta)
    assertEquals(0f, emb[2], delta)
    assertEquals(0f, emb[3], delta)
  }

  @Test
  fun `embedder input is one minus sigma scaled by 1000`() {
    assertEquals(1000f, ZImageHostLoop.embedderInput(0f), delta)
    assertEquals(0f, ZImageHostLoop.embedderInput(1f), delta)
    assertEquals(500f, ZImageHostLoop.embedderInput(0.5f), delta)
  }

  @Test
  fun `silu matches x times sigmoid`() {
    for (v in floatArrayOf(-8f, -1f, 0f, 0.5f, 3f, 20f)) {
      val expected = v * (1.0 / (1.0 + Math.exp(-v.toDouble())))
      assertEquals(expected.toFloat(), ZImageHostLoop.silu(v), delta)
    }
  }

  @Test
  fun `timestep embedder chains embedding then two linears with silu`() {
    // Collapse the MLP to out[k] = silu(embedding[0]) for every k, which
    // exercises embedderInput -> timestepEmbedding -> silu -> both Linear layers.
    val w0 = FloatArray(ZImageHostLoop.TIME_EMBED_MID * ZImageHostLoop.TIME_EMBED_DIM)
    for (i in 0 until ZImageHostLoop.TIME_EMBED_MID) {
      w0[i * ZImageHostLoop.TIME_EMBED_DIM] = 1f
    }
    val w2 = FloatArray(ZImageHostLoop.TIME_EMBED_DIM * ZImageHostLoop.TIME_EMBED_MID)
    for (k in 0 until ZImageHostLoop.TIME_EMBED_DIM) {
      w2[k * ZImageHostLoop.TIME_EMBED_MID] = 1f
    }
    val weights = ZImageHostLoop.TimestepEmbedderWeights(
      mlp0Weight = w0,
      mlp0Bias = FloatArray(ZImageHostLoop.TIME_EMBED_MID),
      mlp2Weight = w2,
      mlp2Bias = FloatArray(ZImageHostLoop.TIME_EMBED_DIM),
    )

    val sigma = 0.25f
    val out = ZImageHostLoop.timestepEmbeddingForSigma(sigma, weights)
    assertEquals(ZImageHostLoop.TIME_EMBED_DIM, out.size)

    val t = ZImageHostLoop.embedderInput(sigma)
    val expected = ZImageHostLoop.silu(cos(t))
    for (k in out.indices) {
      assertEquals(expected, out[k], delta)
    }
  }

  // ------------------------------------------------------------ sigma schedule

  @Test
  fun `default sigmas are linspace from one down to one over steps`() {
    assertArrayEquals(
      floatArrayOf(1.0f, 0.875f, 0.75f, 0.625f, 0.5f, 0.375f, 0.25f, 0.125f),
      ZImageHostLoop.defaultSigmas(8),
      delta,
    )
    assertArrayEquals(floatArrayOf(1f), ZImageHostLoop.defaultSigmas(1), delta)
  }

  @Test
  fun `shift at 256 pixels is exactly 0_5`() {
    assertEquals(0.5f, ZImageHostLoop.calculateShift(256), delta)
  }

  @Test
  fun `time shift leaves sigma of one untouched`() {
    assertEquals(1f, ZImageHostLoop.timeShift(0.5f, 1f), delta)
  }

  @Test
  fun `sigma schedule has steps plus a terminal zero and is decreasing`() {
    val steps = 8
    val schedule = ZImageHostLoop.sigmaSchedule(steps, seqLen = 256)
    assertEquals(steps + 1, schedule.size)
    assertEquals(0f, schedule[steps], 0f)
    for (i in 0 until steps) {
      assertTrue("sigma[$i] must exceed sigma[${i + 1}]", schedule[i] > schedule[i + 1])
    }
  }

  @Test
  fun `shift compresses the tail of the schedule`() {
    val schedule = ZImageHostLoop.sigmaSchedule(8, seqLen = 256)
    val raw = ZImageHostLoop.defaultSigmas(8)
    val mu = ZImageHostLoop.calculateShift(256)
    for (i in 0 until 8) {
      assertEquals(ZImageHostLoop.timeShift(mu, raw[i]), schedule[i], delta)
    }
  }

  // ------------------------------------------------------------ denoising math

  @Test
  fun `classifier free guidance negates after combining branches`() {
    val cond = floatArrayOf(1f, -2f, 0.5f)
    val uncond = floatArrayOf(0f, 1f, 0.5f)
    val guidance = 3.5f
    val out = ZImageHostLoop.applyClassifierFreeGuidance(cond, uncond, guidance)

    for (i in cond.indices) {
      val expected = -(cond[i] + guidance * (cond[i] - uncond[i]))
      assertEquals(expected, out[i], delta)
    }
    // Where cond == uncond the guidance term vanishes, so the result is -cond
    // rather than zero: the negation is applied after CFG, not inside it.
    assertEquals(-0.5f, out[2], delta)
  }

  @Test
  fun `guidance of one doubles the difference against the unconditional branch`() {
    val cond = floatArrayOf(1f, 2f, 3f)
    val uncond = floatArrayOf(9f, 9f, 9f)
    // -(cond + 1 * (cond - uncond)) = -(2*cond - uncond)
    val out = ZImageHostLoop.applyClassifierFreeGuidance(cond, uncond, 1f)
    assertArrayEquals(floatArrayOf(7f, 5f, 3f), out, delta)
  }

  @Test
  fun `euler step moves the latent by dt times the prediction`() {
    val latent = floatArrayOf(1f, 2f, 3f)
    val noise = floatArrayOf(0.5f, -0.5f, 1f)
    val out = ZImageHostLoop.eulerStep(latent, noise, sigma = 0.5f, sigmaNext = 0.25f)
    val dt = 0.25f - 0.5f
    assertEquals(1f + dt * 0.5f, out[0], delta)
    assertEquals(2f + dt * -0.5f, out[1], delta)
    assertEquals(3f + dt * 1f, out[2], delta)
  }

  @Test
  fun `euler step mutates in place`() {
    val latent = floatArrayOf(1f)
    val same = ZImageHostLoop.eulerStep(latent, floatArrayOf(1f), 1f, 0f)
    assertTrue(same === latent)
    assertEquals(0f, latent[0], delta)
  }

  @Test
  fun `denormalisation divides by the scaling factor then shifts`() {
    val latent = floatArrayOf(0f, 0.3611f, 0.7222f)
    val out = ZImageHostLoop.denormalizeLatents(latent)
    assertEquals(0.1159f, out[0], delta)
    assertEquals(1.1159f, out[1], delta)
    assertEquals(2.1159f, out[2], delta)
  }

  @Test
  fun `vaeOutputToUnitRange maps minus one one to zero one`() {
    val unit = ZImageHostLoop.vaeOutputToUnitRange(floatArrayOf(-1f, 0f, 1f, 3f))
    assertEquals(0f, unit[0], delta)
    assertEquals(0.5f, unit[1], delta)
    assertEquals(1f, unit[2], delta)
    assertEquals(1f, unit[3], delta) // clamped
  }

  // ------------------------------------------------------------------- decode

  @Test
  fun `chw output is packed row-major rgb into argb`() {
    // 2x2: red, green / blue, dark blue (already unit-range)
    val rgb = floatArrayOf(
      1f, 0f, 0f, 0f,
      0f, 1f, 0f, 0f,
      0f, 0f, 1f, 0.5f,
    )
    val pixels = ZImageHostLoop.chwToArgb(rgb, 2, 2)
    assertEquals(4, pixels.size)
    assertEquals(0xFFFF0000.toInt(), pixels[0])
    assertEquals(0xFF00FF00.toInt(), pixels[1])
    assertEquals(0xFF0000FF.toInt(), pixels[2])
    // 0.5 * 255 + 0.5 rounds to 128 = 0x80
    assertEquals(0xFF000080.toInt(), pixels[3])
  }

  @Test
  fun `out of range channel values are clamped`() {
    val rgb = floatArrayOf(-1f, 2f, 0f)
    val pixels = ZImageHostLoop.chwToArgb(rgb, 1, 1)
    // red clamps to 0, green clamps to 255, blue is 0
    assertEquals(0xFF00FF00.toInt(), pixels[0])
  }

  @Test
  fun `raw vae minus-one maps to black without unit remap but mid-grey with it`() {
    val raw = floatArrayOf(0f, 0f, 0f) // VAE mid-grey in [-1,1]
    assertEquals(
      0xFF000000.toInt(),
      ZImageHostLoop.chwToArgb(raw, 1, 1)[0],
    )
    val unit = ZImageHostLoop.vaeOutputToUnitRange(raw)
    assertEquals(
      0xFF808080.toInt(),
      ZImageHostLoop.chwToArgb(unit, 1, 1)[0],
    )
  }

  @Test
  fun `decode output is fully opaque`() {
    val rgb = FloatArray(3 * 4) { 0.25f }
    val pixels = ZImageHostLoop.chwToArgb(rgb, 2, 2)
    for (pixel in pixels) {
      assertEquals(0xFF, (pixel shr 24) and 0xFF)
    }
  }

  // ---------------------------------------------------------------- RoPE

  @Test
  fun `captionPosIds start at one on axis zero`() {
    val ids = ZImageHostLoop.captionPosIds(4)
    assertEquals(4, ids.size)
    assertArrayEquals(intArrayOf(1, 0, 0), ids[0])
    assertArrayEquals(intArrayOf(4, 0, 0), ids[3])
  }

  @Test
  fun `imagePosIds place origin after padded caption`() {
    val ids = ZImageHostLoop.imagePosIds(gridH = 2, gridW = 2, capPaddedLen = 32)
    assertEquals(4, ids.size)
    assertArrayEquals(intArrayOf(33, 0, 0), ids[0])
    assertArrayEquals(intArrayOf(33, 0, 1), ids[1])
    assertArrayEquals(intArrayOf(33, 1, 0), ids[2])
    assertArrayEquals(intArrayOf(33, 1, 1), ids[3])
  }

  @Test
  fun `ropeCosSin has unit modulus and expected layout`() {
    val rope = ZImageHostLoop.ropeCosSin(arrayOf(intArrayOf(1, 0, 0)))
    assertEquals(ZImageHostLoop.ROPE_FREQ_DIM, rope.cos.size)
    assertEquals(ZImageHostLoop.ROPE_FREQ_DIM, rope.sin.size)
    // polar(1, angle) → cos^2 + sin^2 == 1
    for (i in rope.cos.indices) {
      val mag2 = rope.cos[i] * rope.cos[i] + rope.sin[i] * rope.sin[i]
      assertEquals(1.0f, mag2, 1e-5f)
    }
    // Index 0 on every axis → angle 0 → cos=1, sin=0 for axis-1 and axis-2 halves.
    // Axis 0 uses index 1: cos(1 * freq0) for first component.
    assertEquals(1.0f, rope.cos[16], delta) // start of axis-1 half
    assertEquals(0.0f, rope.sin[16], delta)
  }

  @Test
  fun `fixed256Rope sizes match LiteRT signatures`() {
    val (cap, img, unified) = ZImageHostLoop.fixed256Rope()
    assertEquals(32 * 64, cap.cos.size)
    assertEquals(256 * 64, img.cos.size)
    assertEquals(288 * 64, unified.cos.size)
    // Unified is [img | cap]
    for (i in img.cos.indices) {
      assertEquals(img.cos[i], unified.cos[i], 0f)
    }
    for (i in cap.cos.indices) {
      assertEquals(cap.cos[i], unified.cos[img.cos.size + i], 0f)
    }
  }

  // ---------------------------------------------------------------- RMSNorm

  @Test
  fun `rmsNorm scales row to unit RMS`() {
    // Single row: [3, 4] should normalize to RMS=1.0
    val flat = floatArrayOf(3f, 4f)
    val out = ZImageHostLoop.rmsNorm(flat, rows = 1, dim = 2)
    val rmsIn = kotlin.math.sqrt(12.5).toFloat()
    assertEquals(3f / rmsIn, out[0], delta)
    assertEquals(4f / rmsIn, out[1], delta)
    val sumSq = out[0] * out[0] + out[1] * out[1]
    val rms = kotlin.math.sqrt(sumSq / 2.0).toFloat()
    assertEquals(1.0f, rms, delta)
  }

  @Test
  fun `rmsNorm handles multiple rows independently`() {
    // Two rows: [1, 2, 3] and [4, 5, 6]
    val flat = floatArrayOf(1f, 2f, 3f, 4f, 5f, 6f)
    val out = ZImageHostLoop.rmsNorm(flat, rows = 2, dim = 3)
    
    // Row 0: RMS = sqrt((1 + 4 + 9)/3) = sqrt(14/3) = 2.1602
    // Row 1: RMS = sqrt((16 + 25 + 36)/3) = sqrt(77/3) = 5.0664
    
    // Each row should have RMS=1.0
    val rms0 = kotlin.math.sqrt(
      (out[0] * out[0] + out[1] * out[1] + out[2] * out[2]) / 3.0
    ).toFloat()
    val rms1 = kotlin.math.sqrt(
      (out[3] * out[3] + out[4] * out[4] + out[5] * out[5]) / 3.0
    ).toFloat()
    
    assertEquals(1.0f, rms0, delta)
    assertEquals(1.0f, rms1, delta)
  }

  @Test
  fun `rmsNorm handles extreme values without overflow`() {
    // Simulate qwen_enc DIAG8 scale: std=46.8, max=7532
    val flat = floatArrayOf(7532f, -2696f, 100f, -500f)
    val out = ZImageHostLoop.rmsNorm(flat, rows = 1, dim = 4)
    
    // Should normalize without NaN or Inf
    for (v in out) {
      assertFalse("NaN in output", v.isNaN())
      assertFalse("Inf in output", v.isInfinite())
    }
    
    // Verify RMS=1.0
    val sumSq = out.fold(0.0) { acc, v -> acc + v * v }
    val rms = kotlin.math.sqrt(sumSq / out.size).toFloat()
    assertEquals(1.0f, rms, delta)
  }
}
