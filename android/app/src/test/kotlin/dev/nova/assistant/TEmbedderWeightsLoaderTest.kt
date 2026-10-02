package dev.nova.assistant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Loader against a synthetic full-shape (all-zero) `t_embedder` file.
 * Shapes match the documented table, so this also proves the ~2 MB
 * streaming read path without staging real weights.
 */
class TEmbedderWeightsLoaderTest {
  @get:Rule
  val temp = TemporaryFolder()

  private fun writeTEmbedder(shapes: Map<String, List<Int>>): File {
    val header = buildString {
      append("{")
      var cursor = 0
      shapes.entries.forEachIndexed { i, (name, shape) ->
        val elements = shape.fold(1) { a, b -> a * b }
        if (i > 0) append(",")
        append(
          "\"$name\":{\"dtype\":\"F32\",\"shape\":[${shape.joinToString(",")}]," +
            "\"data_offsets\":[$cursor,${cursor + elements * 4}]}",
        )
        cursor += elements * 4
      }
      append("}")
    }
    val file = File(temp.newFolder(), "t_embedder.safetensors")
    RandomAccessFile(file, "rw").use { raf ->
      val json = header.toByteArray(Charsets.UTF_8)
      val prefix = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN)
      prefix.putLong(json.size.toLong())
      raf.write(prefix.array())
      raf.write(json)
      val total = shapes.values.sumOf { shape -> shape.fold(1) { a, b -> a * b } } * 4
      var remaining = total
      val zeros = ByteArray(65536)
      while (remaining > 0) {
        val want = minOf(remaining, zeros.size)
        raf.write(zeros, 0, want)
        remaining -= want
      }
    }
    return file
  }

  private fun fullShapes(): Map<String, List<Int>> = mapOf(
    "t_embedder.mlp.0.weight" to listOf(1024, 256),
    "t_embedder.mlp.0.bias" to listOf(1024),
    "t_embedder.mlp.2.weight" to listOf(256, 1024),
    "t_embedder.mlp.2.bias" to listOf(256),
  )

  @Test
  fun `loads full-shape weights`() {
    val weights = TEmbedderWeightsLoader.load(writeTEmbedder(fullShapes()))
    assertEquals(1024 * 256, weights.mlp0Weight.size)
    assertEquals(1024, weights.mlp0Bias.size)
    assertEquals(256 * 1024, weights.mlp2Weight.size)
    assertEquals(256, weights.mlp2Bias.size)
    assertTrue(weights.mlp0Bias.all { it == 0f })

    // Zero weights reduce pos to bias-free SiLU(0)=0 → mlp2(0)+bias(0) = 0.
    val pos = ZImageHostLoop.timestepEmbeddingForSigma(0.5f, weights)
    assertEquals(256, pos.size)
    assertTrue(pos.all { it == 0f })
  }

  @Test(expected = IllegalStateException::class)
  fun `missing tensor fails with name`() {
    writeTEmbedder(
      mapOf("t_embedder.mlp.0.weight" to listOf(1024, 256)),
    ).let { TEmbedderWeightsLoader.load(it) }
  }
}
