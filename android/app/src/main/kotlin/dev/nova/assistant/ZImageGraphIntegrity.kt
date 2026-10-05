package dev.nova.assistant

import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest

/**
 * SHA-256 integrity gate for the 13 published Z-Image Turbo `.tflite` graphs.
 *
 * Pure JVM (no Android imports) so checks run in unit tests and on-device.
 * Shapes alone cannot catch a corrupt graph: the on-device `qwen_enc.tflite`
 * matched the published byte size exactly yet produced std-5e10 outputs from
 * sane inputs, and every `require()` shape check passed. A single flipped
 * weight bit loads fine (zero-input probes still return zeros) while
 * detonating real runs into multi-minute noise generations, so the bytes
 * themselves must be verified against the HuggingFace LFS SHA-256 oids of
 * `litert-community/Z-Image-Turbo-LiteRT`.
 *
 * Hashing ~10 GB takes tens of seconds, so verified files are remembered in
 * a `.zimage_integrity.json` marker keyed by `(size, lastModified)`. Only
 * files whose size/mtime changed are re-hashed. The marker is a cache, never
 * trusted over the bytes: any mismatch fails closed with an actionable
 * message (delete + reinstall) instead of burning battery on static.
 */
object ZImageGraphIntegrity {
  data class Expected(val sizeBytes: Long, val sha256Hex: String)

  /**
   * File sizes and LFS SHA-256 oids from the upstream tree API. If upstream
   * re-publishes a graph, both entries must be updated together here.
   */
  val EXPECTED: Map<String, Expected> = mapOf(
    "qwen_enc.tflite" to Expected(3547652208L, "dcf34ad23b5d821af588d04069e9c791e8acef57353b670a3672d46bce0a1bbb"),
    "z_embc.tflite" to Expected(9906096L, "7a5e74bc94aa4ad22f00625f5f91f8a667e85fc4b363db6016f4cdd6899c97a9"),
    "z_embx.tflite" to Expected(308272L, "ae0da56751ed472bfd8b49cdd5c6fd6dfeed8da0373ab66a2296502d5235926f"),
    "z_refc.tflite" to Expected(355025040L, "60fa7de5be394bfa1fd57781398842ff6eaf446b8b004f78d5c9ab475f76c000"),
    "z_refx.tflite" to Expected(363386160L, "0d5032718a72607ae2f7ee7ae27d7c40e2ded6b119e79b4a12e9d6099da50e37"),
    "zc_final.tflite" to Expected(1295936L, "4e1397197950d71b723f2db06834faa65be71c0b8bd54f9d397c69b9f3b0eb56"),
    "zc_main0.tflite" to Expected(908480960L, "55c7bf5154ae7ecfd177407e7c1da9a908e171c3a1862d53b02b2e24817a6ecc"),
    "zc_main1.tflite" to Expected(908480960L, "ee139fa3937cfded45cd251f49615749e3f48084d8da68206ba98ad4ce9a7288"),
    "zc_main2.tflite" to Expected(908480960L, "033019c34fc0c955a208dcf876abc9339fef1f8f8f321dbbce2bb429758ffb80"),
    "zc_main3.tflite" to Expected(908480960L, "ef70c436fa8ae5b30a0830541de0e84ea9dc97133f231a17e24e8b173e02b677"),
    "zc_main4.tflite" to Expected(908480960L, "fc81daaeac09c89966ec916d1b1b5f0852cfeb2cb0457439ee66e8264e69e512"),
    "zc_main5.tflite" to Expected(908480960L, "4b6c24153aa3c825c668ac9310fc1497d029e8d45c1d115714f564d8e200789f"),
    "zvae.tflite" to Expected(50139872L, "7e2a583027096abfe0411d338dcc6df19c2ee7ea33f65df3b1caaa75304cf350"),
  )

  const val MARKER_NAME = ".zimage_integrity.json"

  sealed interface CheckResult {
    data object Ok : CheckResult
    data class Failed(val reasons: List<String>) : CheckResult
  }

  /**
   * Verifies every expected graph in [modelDir]. Files absent from [expected]
   * (tokenizer, safetensors assets) are ignored. Marker hits skip re-hashing;
   * the marker is rewritten only with freshly verified entries.
   */
  fun verify(
    modelDir: File,
    expected: Map<String, Expected> = EXPECTED,
    hashOf: (File) -> String = ::sha256OfFile,
  ): CheckResult {
    val reasons = ArrayList<String>()
    val marker = readMarker(File(modelDir, MARKER_NAME))
    val verified = HashMap<String, MarkerEntry>()
    // Preserve entries for files that still match; drop the rest.
    for ((name, entry) in marker) {
      val file = File(modelDir, name)
      if (expected.containsKey(name) && file.isFile &&
        file.length() == entry.size && file.lastModified() == entry.mtime
      ) {
        verified[name] = entry
      }
    }
    for ((name, want) in expected) {
      val file = File(modelDir, name)
      if (!file.isFile) {
        reasons.add("$name: missing at ${file.absolutePath}")
        continue
      }
      if (file.length() != want.sizeBytes) {
        reasons.add(
          "$name: size ${file.length()} != published ${want.sizeBytes} " +
            "(truncated or stale download)",
        )
        continue
      }
      val cached = verified[name]
      if (cached != null && cached.sha256.equals(want.sha256Hex, ignoreCase = true)) {
        continue
      }
      val actual = try {
        hashOf(file)
      } catch (e: Throwable) {
        reasons.add("$name: could not hash (${e.message})")
        continue
      }
      if (!actual.equals(want.sha256Hex, ignoreCase = true)) {
        reasons.add(
          "$name: SHA-256 mismatch (corrupt or foreign file). " +
            "Delete it and reinstall the model.",
        )
        continue
      }
      verified[name] = MarkerEntry(file.length(), file.lastModified(), actual)
    }
    if (reasons.isNotEmpty()) return CheckResult.Failed(reasons)
    writeMarker(File(modelDir, MARKER_NAME), verified, expected.keys)
    return CheckResult.Ok
  }

  fun sha256OfFile(file: File): String {
    val digest = MessageDigest.getInstance("SHA-256")
    val buffer = ByteArray(8 * 1024 * 1024)
    FileInputStream(file).use { stream ->
      while (true) {
        val read = stream.read(buffer)
        if (read <= 0) break
        digest.update(buffer, 0, read)
      }
    }
    return digest.digest().joinToString("") { "%02x".format(it) }
  }

  private data class MarkerEntry(val size: Long, val mtime: Long, val sha256: String)

  private fun readMarker(marker: File): Map<String, MarkerEntry> {
    val out = HashMap<String, MarkerEntry>()
    if (!marker.isFile) return out
    try {
      marker.forEachLine { line ->
        val parts = line.split('|')
        if (parts.size != 4) return@forEachLine
        val size = parts[1].toLongOrNull() ?: return@forEachLine
        val mtime = parts[2].toLongOrNull() ?: return@forEachLine
        if (parts[0].isNotEmpty() && parts[3].length == 64) {
          out[parts[0]] = MarkerEntry(size, mtime, parts[3])
        }
      }
    } catch (_: Throwable) {
      return emptyMap()
    }
    return out
  }

  private fun writeMarker(marker: File, entries: Map<String, MarkerEntry>, names: Set<String>) {
    try {
      val text = StringBuilder()
      for (name in names.sorted()) {
        val entry = entries[name] ?: continue
        text.append(name).append('|').append(entry.size).append('|')
          .append(entry.mtime).append('|').append(entry.sha256).append('\n')
      }
      marker.writeText(text.toString())
    } catch (_: Throwable) {
      // Marker is a pure speedup cache; losing it only costs re-hashing.
    }
  }
}
