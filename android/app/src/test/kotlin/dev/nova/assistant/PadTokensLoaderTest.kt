package dev.nova.assistant

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

class PadTokensLoaderTest {
  @get:Rule
  val temp = TemporaryFolder()

  @Test
  fun `loads F32 pad tokens with shape 1x3840`() {
    val cap = FloatArray(3840) { it * 0.001f }
    val x = FloatArray(3840) { it * -0.001f }
    val file = File(temp.newFolder(), "pad_tokens.safetensors")
    writePadFile(file, cap, x, shape = listOf(1, 3840))

    val loaded = PadTokensLoader.load(file)
    assertArrayEquals(cap, loaded.capPadToken, 1e-6f)
    assertArrayEquals(x, loaded.xPadToken, 1e-6f)
  }

  @Test
  fun `loads F32 pad tokens with shape 3840`() {
    val cap = FloatArray(3840) { 1f }
    val x = FloatArray(3840) { 2f }
    val file = File(temp.newFolder(), "pad_tokens.safetensors")
    writePadFile(file, cap, x, shape = listOf(3840))

    val loaded = PadTokensLoader.load(file)
    assertEquals(3840, loaded.capPadToken.size)
    assertEquals(1f, loaded.capPadToken[0], 0f)
    assertEquals(2f, loaded.xPadToken[0], 0f)
  }

  private fun writePadFile(
    file: File,
    cap: FloatArray,
    x: FloatArray,
    shape: List<Int>,
  ) {
    val capBytes = floatBytes(cap)
    val xBytes = floatBytes(x)
    val shapeJson = shape.joinToString(",")
    val header =
      """{"cap_pad_token":{"dtype":"F32","shape":[$shapeJson],"data_offsets":[0,${capBytes.size}]},""" +
        """"x_pad_token":{"dtype":"F32","shape":[$shapeJson],"data_offsets":[${capBytes.size},${capBytes.size + xBytes.size}]}}"""
    RandomAccessFile(file, "rw").use { raf ->
      val json = header.toByteArray(Charsets.UTF_8)
      val prefix = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN)
      prefix.putLong(json.size.toLong())
      raf.write(prefix.array())
      raf.write(json)
      raf.write(capBytes)
      raf.write(xBytes)
    }
  }

  private fun floatBytes(v: FloatArray): ByteArray {
    val buf = ByteBuffer.allocate(v.size * 4).order(ByteOrder.LITTLE_ENDIAN)
    for (f in v) buf.putFloat(f)
    return buf.array()
  }
}
