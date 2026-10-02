package dev.nova.assistant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import dev.nova.assistant.SafetensorsHeaderCheck.ok
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Header pre-check against synthetic safetensors files. Mirrors the
 * Dart-side `verifyDerivedAssets` contract: exact dtype + shape, offsets
 * inside the file, fail-closed reasons instead of throws.
 */
class SafetensorsHeaderCheckTest {
  @get:Rule
  val temp = TemporaryFolder()

  private fun writeFile(headerJson: String, payload: ByteArray): File {
    val file = File(temp.newFolder(), "test.safetensors")
    RandomAccessFile(file, "rw").use { raf ->
      val json = headerJson.toByteArray(Charsets.UTF_8)
      val prefix = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN)
      prefix.putLong(json.size.toLong())
      raf.write(prefix.array())
      raf.write(json)
      raf.write(payload)
    }
    return file
  }

  private val embedHeader = """
    {"embed_tokens":{"dtype":"BF16","shape":[4,3],"data_offsets":[0,24]},
     "other":{"dtype":"F32","shape":[2],"data_offsets":[24,32]}}
  """.trimIndent()

  @Test
  fun `valid header passes`() {
    val file = writeFile(embedHeader, ByteArray(32))
    val result = SafetensorsHeaderCheck.checkFile(
      file,
      listOf(SafetensorsHeaderCheck.ExpectedTensor("embed_tokens", "BF16", listOf(4, 3))),
    )
    assertTrue(result.ok)
  }

  @Test
  fun `missing tensor fails with name`() {
    val file = writeFile(embedHeader, ByteArray(32))
    val result = SafetensorsHeaderCheck.checkFile(
      file,
      listOf(SafetensorsHeaderCheck.ExpectedTensor("absent", "BF16", listOf(4, 3))),
    )
    assertFalse(result.ok)
    val reasons = (result as SafetensorsHeaderCheck.CheckResult.Failed).reasons
    assertTrue(reasons.any { it.contains("absent") })
  }

  @Test
  fun `wrong dtype and shape fail`() {
    val file = writeFile(embedHeader, ByteArray(32))
    val dtypeResult = SafetensorsHeaderCheck.checkFile(
      file,
      listOf(SafetensorsHeaderCheck.ExpectedTensor("embed_tokens", "F32", listOf(4, 3))),
    )
    assertFalse(dtypeResult.ok)
    val shapeResult = SafetensorsHeaderCheck.checkFile(
      file,
      listOf(SafetensorsHeaderCheck.ExpectedTensor("embed_tokens", "BF16", listOf(4, 4))),
    )
    assertFalse(shapeResult.ok)
  }

  @Test
  fun `offsets past EOF fail instead of mmap-crashing later`() {
    val header = """{"big":{"dtype":"F32","shape":[100],"data_offsets":[0,400]}}"""
    val file = writeFile(header, ByteArray(8))
    val result = SafetensorsHeaderCheck.checkFile(
      file,
      listOf(SafetensorsHeaderCheck.ExpectedTensor("big", "F32", listOf(100))),
    )
    assertFalse(result.ok)
  }

  @Test(expected = IllegalArgumentException::class)
  fun `truncated header throws`() {
    val file = File(temp.newFolder(), "short.safetensors")
    RandomAccessFile(file, "rw").use { raf ->
      val prefix = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN)
      prefix.putLong(1_000_000L)
      raf.write(prefix.array())
      raf.write(ByteArray(10))
    }
    SafetensorsHeaderCheck.parseHeader(file)
  }

  @Test(expected = IllegalArgumentException::class)
  fun `garbage json throws`() {
    val file = File(temp.newFolder(), "garbage.safetensors")
    RandomAccessFile(file, "rw").use { raf ->
      val json = "not json{{{".toByteArray(Charsets.UTF_8)
      val prefix = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN)
      prefix.putLong(json.size.toLong())
      raf.write(prefix.array())
      raf.write(json)
    }
    SafetensorsHeaderCheck.parseHeader(file)
  }

  @Test
  fun `derived check on empty dir fails with both files named`() {
    val dir = temp.newFolder("empty-model")
    val result = SafetensorsHeaderCheck.checkDerivedAssets(dir)
    assertFalse(result.ok)
    val reasons = (result as SafetensorsHeaderCheck.CheckResult.Failed).reasons
    assertEquals(2, reasons.size)
    assertTrue(reasons.any { it.contains("embed_tokens.safetensors") })
    assertTrue(reasons.any { it.contains("t_embedder.safetensors") })
  }

  @Test
  fun `derived check rejects wrong-shaped staged files`() {
    // Small impostor files: present on disk but not the documented tensors.
    val dir = temp.newFolder("model")
    writeInto(
      File(dir, "embed_tokens.safetensors"),
      """{"embed_tokens":{"dtype":"BF16","shape":[8,8],"data_offsets":[0,128]}}""",
      ByteArray(128),
    )
    writeInto(
      File(dir, "t_embedder.safetensors"),
      """{"t_embedder.mlp.0.weight":{"dtype":"F32","shape":[2,2],"data_offsets":[0,16]}}""",
      ByteArray(16),
    )
    val result = SafetensorsHeaderCheck.checkDerivedAssets(dir)
    assertFalse(result.ok)
  }

  @Test
  fun `documented constants match the verified signatures`() {
    // Guards against silent drift from docs/z-image-turbo-litert.md.
    assertEquals("embed_tokens", SafetensorsHeaderCheck.EXPECTED_EMBED_TOKENS.name)
    assertEquals("BF16", SafetensorsHeaderCheck.EXPECTED_EMBED_TOKENS.dtype)
    assertEquals(listOf(151936, 2560), SafetensorsHeaderCheck.EXPECTED_EMBED_TOKENS.shape)
    val tNames = SafetensorsHeaderCheck.EXPECTED_T_EMBEDDER.map { it.name }
    assertEquals(
      listOf(
        "t_embedder.mlp.0.weight",
        "t_embedder.mlp.0.bias",
        "t_embedder.mlp.2.weight",
        "t_embedder.mlp.2.bias",
      ),
      tNames,
    )
    assertTrue(SafetensorsHeaderCheck.EXPECTED_T_EMBEDDER.all { it.dtype == "F32" })
  }

  private fun writeInto(file: File, headerJson: String, payload: ByteArray) {
    RandomAccessFile(file, "rw").use { raf ->
      val json = headerJson.toByteArray(Charsets.UTF_8)
      val prefix = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN)
      prefix.putLong(json.size.toLong())
      raf.write(prefix.array())
      raf.write(json)
      raf.write(payload)
    }
  }
}
