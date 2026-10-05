package dev.nova.assistant

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * End-to-end 256 px run against fake graphs: every stage executes in order
 * with shape-checked I/O (tokenize → embed → `qwen_enc` → context → DiT
 * loop with CFG → `zvae`). The fakes transform their inputs deterministically
 * so this proves wiring, sequencing, and math — not weights.
 */
class ZImagePipelineTest {
  private class FakeGraphs : ZImageGraphs {
    val calls = ArrayList<String>()
    val inputSizes = HashMap<String, ArrayList<Int>>()
    var releases = 0

    private fun record(name: String, vararg sizes: Int): String {
      calls.add(name)
      inputSizes.getOrPut(name) { ArrayList() }.addAll(sizes.toList())
      return name
    }

    private fun tilePlus(input: FloatArray, outSize: Int, c: Float): FloatArray {
      val out = FloatArray(outSize)
      for (i in out.indices) out[i] = input[i % input.size] + c
      return out
    }

    override fun qwenEnc(embeds: FloatArray): FloatArray {
      record("qwenEnc", embeds.size)
      require(embeds.size == 64 * 2560) { "qwen in" }
      return embeds.copyOf()
    }

    override fun embx(img: FloatArray): FloatArray {
      record("embx", img.size)
      require(img.size == 256 * 64) { "embx in" }
      return tilePlus(img, 256 * 3840, 0.5f)
    }

    override fun refx(cap: FloatArray, x: FloatArray, mask: FloatArray, pos: FloatArray): FloatArray {
      record("refx", cap.size, x.size, mask.size, pos.size)
      require(cap.size == 256 * 3840 && x.size == 256 * 64 && mask.size == 256 * 64 && pos.size == 256) {
        "refx shapes"
      }
      return FloatArray(cap.size) { cap[it] + 0.25f }
    }

    override fun embc(cap: FloatArray): FloatArray {
      record("embc", cap.size)
      require(cap.size == 32 * 2560) { "embc in" }
      return tilePlus(cap, 32 * 3840, 0.5f)
    }

    override fun refc(cap: FloatArray, x: FloatArray, mask: FloatArray): FloatArray {
      record("refc", cap.size, x.size, mask.size)
      require(cap.size == 32 * 3840 && x.size == 32 * 64 && mask.size == 32 * 64) {
        "refc shapes"
      }
      return FloatArray(cap.size) { cap[it] + 0.25f }
    }

    override fun mainBlock(index: Int, hidden: FloatArray, x: FloatArray, mask: FloatArray, pos: FloatArray): FloatArray {
      record("main$index", hidden.size, x.size, mask.size, pos.size)
      require(hidden.size == 288 * 3840 && x.size == 288 * 64 && mask.size == 288 * 64 && pos.size == 256) {
        "main$index shapes"
      }
      // Mimic attention mixing: the context tail shifts every row, so branch
      // contexts (and therefore CFG guidance) actually move the output.
      var tailSum = 0.0
      for (r in 256 until 288) {
        for (c in 0 until 3840) tailSum += hidden[r * 3840 + c]
      }
      val tailMean = (tailSum / (32 * 3840)).toFloat()
      return FloatArray(hidden.size) { hidden[it] + (index + 1) * 0.1f + tailMean }
    }

    override fun final(hidden: FloatArray, pos: FloatArray): FloatArray {
      record("final", hidden.size, pos.size)
      require(hidden.size == 288 * 3840 && pos.size == 256) { "final shapes" }
      // First 64 cols per row, nudged by pos so sigma/timestep matters.
      val out = FloatArray(288 * 64)
      for (r in 0 until 288) {
        for (c in 0 until 64) {
          out[r * 64 + c] = hidden[r * 3840 + c] + pos[c % 256] * 0.01f
        }
      }
      return out
    }

    override fun vae(latentChw: FloatArray): FloatArray {
      record("vae", latentChw.size)
      require(latentChw.size == 16 * 32 * 32) { "vae in" }
      val out = FloatArray(3 * 256 * 256)
      for (c in 0 until 3) {
        for (p in 0 until 256 * 256) {
          out[c * 65536 + p] = latentChw[c * 1024 + p % 1024] * 0.01f + c
        }
      }
      return out
    }

    override fun releaseTextEncoder() {
      record("releaseText")
    }

    override fun releaseContextGraphs() {
      record("releaseCtx")
    }

    override fun releaseDenoiseGraphs() {
      record("releaseDenoise")
      releases++
    }

    override fun releaseVae() {
      record("releaseVae")
    }

    override fun close() {
      record("close")
    }
  }

  private val weights = ZImageHostLoop.TimestepEmbedderWeights(
    mlp0Weight = FloatArray(1024 * 256),
    mlp0Bias = FloatArray(1024),
    mlp2Weight = FloatArray(256 * 1024),
    mlp2Bias = FloatArray(256),
  )

  private fun tokenize(text: String): IntArray =
    if (text.isEmpty()) IntArray(0) else IntArray(10) { it + 1 }

  private fun rowsOf(ids: IntArray): Array<FloatArray> =
    Array(ids.size) { r -> FloatArray(2560) { c -> (r * 2560 + c).toFloat() * 1e-4f } }

  private val req = ZImagePipeline.Request(
    prompt = "a cat",
    steps = 1,
    guidance = 1.0f,
    seed = 7L,
  )

  @Test
  fun `full 256px run returns RGB CHW with expected call counts`() {
    val graphs = FakeGraphs()
    val rgb = ZImagePipeline.generate(graphs, ::tokenize, ::rowsOf, weights, req)

    assertEquals(3 * 256 * 256, rgb.size)

    fun count(name: String) = graphs.calls.count { it == name }
    assertEquals(2, count("qwenEnc"))
    assertEquals(2, count("embc"))
    assertEquals(2, count("refc"))
    // 1 step x 2 branches.
    assertEquals(2, count("embx"))
    assertEquals(2, count("refx"))
    assertEquals(2, count("final"))
    assertEquals(1, count("vae"))
    for (i in 0..5) assertEquals(2, count("main$i"))

    // Phase discipline: text + context released before denoise ends.
    val releaseTextAt = graphs.calls.indexOf("releaseText")
    val firstMain = graphs.calls.indexOf("main0")
    assertTrue(releaseTextAt >= 0 && releaseTextAt < firstMain)
    assertTrue(graphs.calls.contains("releaseDenoise"))
    assertTrue(graphs.calls.contains("releaseVae"))
  }

  @Test
  fun `guidance zero runs one DiT sweep and skips the uncond branch`() {
    val graphs = FakeGraphs()
    val steps = 3
    ZImagePipeline.generate(graphs, ::tokenize, ::rowsOf, weights, req.copy(steps = steps, guidance = 0f))

    fun count(name: String) = graphs.calls.count { it == name }
    // `do_classifier_free_guidance == guidance_scale > 0`, so no uncond text
    // branch is encoded and the six 908 MB blocks are swept once per step.
    assertEquals(1, count("qwenEnc"))
    assertEquals(1, count("embc"))
    assertEquals(1, count("refc"))
    assertEquals(steps, count("embx"))
    assertEquals(steps, count("refx"))
    assertEquals(steps, count("final"))
    for (i in 0..5) assertEquals(steps, count("main$i"))
    assertEquals(1, count("vae"))
  }

  @Test
  fun `guidance zero negates the single branch`() {
    // At guidance 0 `-(cond + 0 * (cond - uncond))` reduces to `-cond`, which
    // is the pipeline's unconditional `noise_pred = -noise_pred`.
    val cond = floatArrayOf(1f, -2f, 0.5f)
    assertArrayEquals(
      floatArrayOf(-1f, 2f, -0.5f),
      ZImageHostLoop.applyClassifierFreeGuidance(cond, cond, 0f),
      0f,
    )
  }

  @Test
  fun `run is deterministic for a fixed seed`() {
    val first = ZImagePipeline.generate(FakeGraphs(), ::tokenize, ::rowsOf, weights, req)
    val second = ZImagePipeline.generate(FakeGraphs(), ::tokenize, ::rowsOf, weights, req)
    assertArrayEquals(first, second, 0f)
  }

  @Test
  fun `guidance and steps change the output`() {
    val base = ZImagePipeline.generate(FakeGraphs(), ::tokenize, ::rowsOf, weights, req)
    val noGuidance = ZImagePipeline.generate(
      FakeGraphs(), ::tokenize, ::rowsOf, weights, req.copy(guidance = 0f),
    )
    assertFalse(base.contentEquals(noGuidance))
    val twoSteps = ZImagePipeline.generate(
      FakeGraphs(), ::tokenize, ::rowsOf, weights, req.copy(steps = 2),
    )
    assertFalse(base.contentEquals(twoSteps))
  }

  @Test
  fun `empty prompt still builds a 32-row context`() {
    val graphs = FakeGraphs()
    val ctx = ZImagePipeline.branchContext(graphs, ::tokenize, ::rowsOf, "")
    assertEquals(32 * 3840, ctx.size)
    assertEquals(listOf(32 * 2560), graphs.inputSizes["embc"])
  }

  @Test
  fun `tensorStats summarizes distribution`() {
    val line = ZImagePipeline.tensorStats("probe", floatArrayOf(1f, 2f, 3f, 4f))
    assertTrue(line.startsWith("probe: n=4 "))
    assertTrue(line.contains("mean=2.5000"))
    assertTrue(line.contains("min=1.0000"))
    assertTrue(line.contains("max=4.0000"))
  }

  @Test
  fun `generate emits log lines at every stage`() {
    val lines = ArrayList<String>()
    ZImagePipeline.generate(
      FakeGraphs(), ::tokenize, ::rowsOf, weights, req, onLog = { lines.add(it) },
    )
    assertTrue(lines.any { it.startsWith("condCtx:") })
    assertTrue(lines.any { it.startsWith("paddedIn:") })
    assertTrue(lines.any { it.startsWith("latent0:") })
    assertTrue(lines.any { it.startsWith("sigmas=") })
    assertTrue(lines.any { it.startsWith("pos0:") })
    assertTrue(lines.any { it.startsWith("capFeats:") })
    assertTrue(lines.any { it.startsWith("capFeatsPad:") })
    assertTrue(lines.any { it.startsWith("capFeatsReal:") })
    assertTrue(lines.any { it.startsWith("ctxEmbc:") })
    assertTrue(lines.any { it.startsWith("ctxRefc:") })
    assertTrue(lines.any { it.startsWith("s0Embx:") })
    assertTrue(lines.any { it.startsWith("s0Refx:") })
    assertTrue(lines.any { it.startsWith("s0Main0:") })
    assertTrue(lines.any { it.startsWith("s0Main5:") })
    assertTrue(lines.any { it.startsWith("s0Final:") })
    assertTrue(lines.any { it.startsWith("condNoise0:") })
    assertTrue(lines.any { it.startsWith("step1/1 latent:") })
    assertTrue(lines.any { it.startsWith("denorm:") })
    assertTrue(lines.any { it.startsWith("rgb:") })
  }

  @Test
  fun `branchContext splits capFeats into pad and real regions`() {
    val lines = ArrayList<String>()
    // Test tokenize yields 10 ids: 54 zero pad rows, 10 real rows echoed
    // back by FakeGraphs.qwenEnc.
    ZImagePipeline.branchContext(FakeGraphs(), ::tokenize, ::rowsOf, "a cat", onLog = { lines.add(it) })
    assertTrue(lines.any { it.startsWith("paddedIn:") })
    val pad = lines.firstOrNull { it.startsWith("capFeatsPad:") }
    val real = lines.firstOrNull { it.startsWith("capFeatsReal:") }
    assertTrue(pad != null && pad.contains("n=138240") && pad.contains("mean=0.0000") && pad.contains("std=0.0000"))
    // Real rows are (r * 2560 + c) * 1e-4 for r in 0..9 (n=25600, mean ~1.28).
    // Parsed with tolerance: float summation order must not decide the test.
    val realMean = real?.let { Regex("mean=(-?[0-9.]+)").find(it)?.groupValues?.get(1)?.toDoubleOrNull() }
    assertTrue(real != null && real.contains("n=25600") && realMean != null && realMean > 1.2 && realMean < 1.4)
  }

  @Test
  fun `branchContext with empty prompt logs pad region but no real region`() {
    val lines = ArrayList<String>()
    ZImagePipeline.branchContext(FakeGraphs(), ::tokenize, ::rowsOf, "", onLog = { lines.add(it) })
    assertTrue(lines.any { it.startsWith("capFeatsPad:") })
    assertTrue(lines.none { it.startsWith("capFeatsReal:") })
  }

  @Test
  fun `gaussian latent is seeded and finite`() {
    val a = ZImagePipeline.gaussianLatent(kotlin.random.Random(3L), 1024)
    val b = ZImagePipeline.gaussianLatent(kotlin.random.Random(3L), 1024)
    assertArrayEquals(a, b, 0f)
    assertTrue(a.all { it.isFinite() })
    assertTrue(a.any { it != 0f })
  }
}
