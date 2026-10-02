package dev.nova.assistant

import org.junit.Assert.assertArrayEquals
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
 * BF16 conversion and row gathering against a synthetic 2-row safetensors
 * matrix. Real `embed_tokens` is [151936,2560] BF16 — same layout, tiny
 * dimensions so the test stays in milliseconds.
 */
class ZImageEmbedLookupTest {
  @get:Rule
  val temp = TemporaryFolder()

  private val delta = 0f

  /** Truncating float→BF16; exact for the test values below. */
  private fun f32(v: Float): Int = (v.toBits() ushr 16) and 0xFFFF

  /** Writes `embed_tokens` [rows x dim] BF16 with `values[row][col]`. */
  private fun writeEmbed(
    dir: File,
    name: String,
    values: Array<FloatArray>,
  ): File {
    val dim = values[0].size
    val headerJson = """
      {"embed_tokens":{"dtype":"BF16","shape":[${values.size},$dim],
       "data_offsets":[0,${values.size * dim * 2}]}}
    """.trimIndent().replace("\n", "")
    val file = File(dir, name)
    RandomAccessFile(file, "rw").use { raf ->
      val json = headerJson.toByteArray(Charsets.UTF_8)
      val prefix = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN)
      prefix.putLong(json.size.toLong())
      raf.write(prefix.array())
      raf.write(json)
      for (row in values) {
        for (v in row) {
          val bits = f32(v)
          raf.write(bits and 0xFF)
          raf.write((bits ushr 8) and 0xFF)
        }
      }
    }
    return file
  }

  @Test
  fun `bf16 conversion matches known bit patterns`() {
    assertEquals(1.0f, ZImageEmbedLookup.bf16ToFloat32(0x3F80), delta)
    assertEquals(2.0f, ZImageEmbedLookup.bf16ToFloat32(0x4000), delta)
    assertEquals(-1.0f, ZImageEmbedLookup.bf16ToFloat32(0xBF80), delta)
    assertEquals(0.0f, ZImageEmbedLookup.bf16ToFloat32(0x0000), delta)
    assertEquals(0.5f, ZImageEmbedLookup.bf16ToFloat32(0x3F00), delta)
    assertEquals(1.0f + 1.0f / 128, ZImageEmbedLookup.bf16ToFloat32(0x3F81), delta)
    assertEquals(Float.POSITIVE_INFINITY, ZImageEmbedLookup.bf16ToFloat32(0x7F80), delta)
    assertTrue(ZImageEmbedLookup.bf16ToFloat32(0x7FC0).isNaN())
  }

  @Test
  fun `gatherRows returns rows in id order`() {
    val dir = temp.newFolder("embed")
    val file = writeEmbed(
      dir,
      "embed_tokens.safetensors",
      arrayOf(
        floatArrayOf(1f, 2f, 3f, 4f),
        floatArrayOf(0.5f, -1f, 8f, 16f),
      ),
    )
    val out = ZImageEmbedLookup.gatherRows(file, intArrayOf(1, 0), dim = 4)
    assertArrayEquals(
      floatArrayOf(0.5f, -1f, 8f, 16f, 1f, 2f, 3f, 4f),
      out,
      delta,
    )
  }

  @Test(expected = IllegalArgumentException::class)
  fun `gatherRows rejects out-of-range ids`() {
    val dir = temp.newFolder("embed-range")
    val file = writeEmbed(dir, "e.safetensors", arrayOf(floatArrayOf(1f, 2f)))
    ZImageEmbedLookup.gatherRows(file, intArrayOf(5), dim = 2)
  }

  @Test(expected = IllegalArgumentException::class)
  fun `gatherRows rejects width mismatch`() {
    val dir = temp.newFolder("embed-width")
    val file = writeEmbed(dir, "e.safetensors", arrayOf(floatArrayOf(1f, 2f)))
    ZImageEmbedLookup.gatherRows(file, intArrayOf(0), dim = 4)
  }

  @Test
  fun `inputsEmbeds left-pads so real rows keep the tail`() {
    val dir = temp.newFolder("embed-pad")
    val file = writeEmbed(
      dir,
      "e.safetensors",
      arrayOf(floatArrayOf(1f, 2f), floatArrayOf(3f, 4f)),
    )
    val out = ZImageEmbedLookup.inputsEmbeds(intArrayOf(1), file, dim = 2, seqLen = 4)
    assertArrayEquals(
      floatArrayOf(0f, 0f, 0f, 0f, 0f, 0f, 3f, 4f),
      out,
      delta,
    )
  }

  @Test
  fun `inputsEmbeds keeps the tail when the prompt overflows`() {
    val dir = temp.newFolder("embed-tail")
    val file = writeEmbed(
      dir,
      "e.safetensors",
      arrayOf(floatArrayOf(1f), floatArrayOf(2f), floatArrayOf(3f)),
    )
    val out = ZImageEmbedLookup.inputsEmbeds(
      intArrayOf(0, 1, 2, 0, 1),
      file,
      dim = 1,
      seqLen = 4,
    )
    assertArrayEquals(floatArrayOf(2f, 3f, 1f, 2f), out, delta)
  }
}
