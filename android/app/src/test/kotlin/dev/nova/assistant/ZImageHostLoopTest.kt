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
  fun `context padding repeats the last real row`() {
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

  // ------------------------------------------------------------------- decode

  @Test
  fun `chw output is packed row-major rgb into argb`() {
    // 2x2: red, green / blue, dark blue
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
  fun `decode output is fully opaque`() {
    val rgb = FloatArray(3 * 4) { 0.25f }
    val pixels = ZImageHostLoop.chwToArgb(rgb, 2, 2)
    for (pixel in pixels) {
      assertEquals(0xFF, (pixel shr 24) and 0xFF)
    }
  }
}
