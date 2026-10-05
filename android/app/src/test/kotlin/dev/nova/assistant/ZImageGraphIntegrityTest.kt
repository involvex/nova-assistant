package dev.nova.assistant

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [ZImageGraphIntegrity] against scratch model dirs: missing/stale/corrupt
 * files fail closed with the file name, exact files pass, and the marker
 * cache avoids re-hashing ~10 GB on every generation.
 */
class ZImageGraphIntegrityTest {
  private fun dir(): File = Files.createTempDirectory("zimage-integrity").toFile()

  private fun write(dir: File, name: String, bytes: ByteArray): File {
    val file = File(dir, name)
    file.writeBytes(bytes)
    return file
  }

  private fun expectedFor(files: Map<String, ByteArray>): Map<String, ZImageGraphIntegrity.Expected> {
    return files.mapValues { (_, bytes) ->
      // Hash through a temp file so the table matches real on-disk hashing.
      val tmp = File.createTempFile("zimage-expect", ".bin")
      try {
        tmp.writeBytes(bytes)
        ZImageGraphIntegrity.Expected(
          bytes.size.toLong(),
          ZImageGraphIntegrity.sha256OfFile(tmp),
        )
      } finally {
        tmp.delete()
      }
    }
  }

  @Test
  fun `sha256 matches the standard test vector`() {
    val tmp = File.createTempFile("zimage-vec", ".bin")
    try {
      tmp.writeBytes("abc".toByteArray(Charsets.UTF_8))
      assertEquals(
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        ZImageGraphIntegrity.sha256OfFile(tmp),
      )
    } finally {
      tmp.delete()
    }
  }

  @Test
  fun `missing file fails with its name`() {
    val modelDir = dir()
    val expected = expectedFor(mapOf("qwen_enc.tflite" to ByteArray(16) { it.toByte() }))
    val result = ZImageGraphIntegrity.verify(modelDir, expected)
    assertTrue(result is ZImageGraphIntegrity.CheckResult.Failed)
    assertTrue((result as ZImageGraphIntegrity.CheckResult.Failed).reasons.any {
      it.contains("qwen_enc.tflite")
    })
  }

  @Test
  fun `wrong size fails without hashing`() {
    val modelDir = dir()
    val bytes = ByteArray(16) { it.toByte() }
    write(modelDir, "zvae.tflite", bytes)
    val expected = expectedFor(mapOf("zvae.tflite" to ByteArray(8) { it.toByte() }))
    var hashed = 0
    val result = ZImageGraphIntegrity.verify(modelDir, expected) {
      hashed++
      ZImageGraphIntegrity.sha256OfFile(it)
    }
    assertTrue(result is ZImageGraphIntegrity.CheckResult.Failed)
    assertEquals(0, hashed)
  }

  @Test
  fun `right size but wrong bytes fails on SHA-256`() {
    val modelDir = dir()
    write(modelDir, "z_embx.tflite", ByteArray(16) { 7 })
    val expected = expectedFor(mapOf("z_embx.tflite" to ByteArray(16) { it.toByte() }))
    val result = ZImageGraphIntegrity.verify(modelDir, expected)
    assertTrue(result is ZImageGraphIntegrity.CheckResult.Failed)
    val reasons = (result as ZImageGraphIntegrity.CheckResult.Failed).reasons
    assertTrue(reasons.any { it.contains("z_embx.tflite") && it.contains("SHA-256") })
  }

  @Test
  fun `exact files pass and second verify skips re-hashing`() {
    val modelDir = dir()
    val payload = mapOf(
      "z_embx.tflite" to ByteArray(16) { it.toByte() },
      "zc_final.tflite" to ByteArray(24) { (it * 3).toByte() },
    )
    for ((name, bytes) in payload) write(modelDir, name, bytes)
    val expected = expectedFor(payload)
    var hashed = 0
    val countingHash = { file: File ->
      hashed++
      ZImageGraphIntegrity.sha256OfFile(file)
    }
    assertTrue(ZImageGraphIntegrity.verify(modelDir, expected, countingHash) is ZImageGraphIntegrity.CheckResult.Ok)
    assertEquals(2, hashed)
    assertTrue(File(modelDir, ZImageGraphIntegrity.MARKER_NAME).isFile)
    // Marker hit: sizes/mtimes unchanged, no file is hashed again.
    assertTrue(ZImageGraphIntegrity.verify(modelDir, expected, countingHash) is ZImageGraphIntegrity.CheckResult.Ok)
    assertEquals(2, hashed)
  }

  @Test
  fun `modified bytes after a pass fail the next verify`() {
    val modelDir = dir()
    val payload = mapOf("zvae.tflite" to ByteArray(16) { it.toByte() })
    write(modelDir, "zvae.tflite", payload.getValue("zvae.tflite"))
    val expected = expectedFor(payload)
    assertTrue(ZImageGraphIntegrity.verify(modelDir, expected) is ZImageGraphIntegrity.CheckResult.Ok)
    // Same size, different bytes: must re-hash (mtime changed) and fail.
    write(modelDir, "zvae.tflite", ByteArray(16) { (it + 1).toByte() })
    val again = ZImageGraphIntegrity.verify(modelDir, expected)
    assertTrue(again is ZImageGraphIntegrity.CheckResult.Failed)
  }

  @Test
  fun `corrupt marker is ignored and files re-verify`() {
    val modelDir = dir()
    val payload = mapOf("zvae.tflite" to ByteArray(16) { it.toByte() })
    write(modelDir, "zvae.tflite", payload.getValue("zvae.tflite"))
    File(modelDir, ZImageGraphIntegrity.MARKER_NAME).writeText("not|valid\n")
    val expected = expectedFor(payload)
    assertTrue(ZImageGraphIntegrity.verify(modelDir, expected) is ZImageGraphIntegrity.CheckResult.Ok)
  }

  @Test
  fun `expected table covers all thirteen published graphs`() {
    assertEquals(13, ZImageGraphIntegrity.EXPECTED.size)
    assertTrue(ZImageGraphIntegrity.EXPECTED.values.all { it.sizeBytes > 0 && it.sha256Hex.length == 64 })
  }
}
