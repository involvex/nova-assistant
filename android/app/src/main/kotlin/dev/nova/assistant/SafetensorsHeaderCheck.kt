package dev.nova.assistant

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Pre-flight validation of staged/extracted safetensors files.
 *
 * Pure JVM (no Android imports) so checks run in unit tests and on-device.
 * Mirrors the Dart-side `ZImageTensorExtraction.verifyDerivedAssets`: before
 * the host mmaps the 778 MB `embed_tokens` matrix (an uncatchable OOM/LMK
 * risk if the file is corrupt), the header must prove the expected tensors
 * exist with the documented dtype + shape and internally consistent offsets.
 */
object SafetensorsHeaderCheck {
  const val MAX_HEADER_BYTES = 32 * 1024 * 1024L

  val BYTES_PER_ELEMENT: Map<String, Int> = mapOf(
    "BOOL" to 1,
    "U8" to 1,
    "I8" to 1,
    "I16" to 2,
    "U16" to 2,
    "F16" to 2,
    "BF16" to 2,
    "I32" to 4,
    "U32" to 4,
    "F32" to 4,
    "F64" to 8,
    "I64" to 8,
    "U64" to 8,
  )

  // ------------------------------------------------------------------ model

  data class ExpectedTensor(
    val name: String,
    val dtype: String,
    val shape: List<Int>,
  )

  data class TensorLayout(
    val dtype: String,
    val shape: List<Int>,
    val start: Long,
    val end: Long,
  )

  data class ParsedHeader(
    val tensors: Map<String, TensorLayout>,
    /** Absolute file offset where tensor bytes begin. */
    val dataStart: Long,
  )

  sealed interface CheckResult {
    data object Ok : CheckResult
    data class Failed(val reasons: List<String>) : CheckResult
  }

  val CheckResult.ok: Boolean get() = this is CheckResult.Ok

  // ------------------------------------------------------- Z-Image derived

  /** `embed_tokens` matrix from `docs/z-image-turbo-litert.md`. */
  val EXPECTED_EMBED_TOKENS = ExpectedTensor(
    "embed_tokens",
    "BF16",
    listOf(151936, 2560),
  )

  /** `t_embedder` MLP tensors, exact names/dtypes/shapes. */
  val EXPECTED_T_EMBEDDER: List<ExpectedTensor> = listOf(
    ExpectedTensor("t_embedder.mlp.0.weight", "F32", listOf(1024, 256)),
    ExpectedTensor("t_embedder.mlp.0.bias", "F32", listOf(1024)),
    ExpectedTensor("t_embedder.mlp.2.weight", "F32", listOf(256, 1024)),
    ExpectedTensor("t_embedder.mlp.2.bias", "F32", listOf(256)),
  )

  /**
   * Mirrors Dart `verifyDerivedAssets`: both extracted files must exist and
   * carry the documented tensors. Returns [CheckResult.Failed] with every
   * reason instead of throwing, so the pipeline can surface one message.
   */
  fun checkDerivedAssets(modelDir: File): CheckResult {
    val reasons = ArrayList<String>()
    val embedFile = File(modelDir, "embed_tokens.safetensors")
    val tEmbedderFile = File(modelDir, "t_embedder.safetensors")
    if (!embedFile.isFile) {
      reasons.add("Missing ${embedFile.absolutePath} (run extraction first)")
    } else {
      checkFile(embedFile, listOf(EXPECTED_EMBED_TOKENS), reasons)
    }
    if (!tEmbedderFile.isFile) {
      reasons.add("Missing ${tEmbedderFile.absolutePath} (run extraction first)")
    } else {
      checkFile(tEmbedderFile, EXPECTED_T_EMBEDDER, reasons)
    }
    return if (reasons.isEmpty()) CheckResult.Ok else CheckResult.Failed(reasons)
  }

  // ------------------------------------------------------------------ check

  /** Validates [expected] against [file]'s header, appending reasons. */
  fun checkFile(
    file: File,
    expected: List<ExpectedTensor>,
    reasons: MutableList<String> = ArrayList(),
  ): CheckResult {
    val header: ParsedHeader = try {
      parseHeader(file)
    } catch (t: Throwable) {
      reasons.add("${file.name}: unreadable header (${t.message})")
      return CheckResult.Failed(reasons)
    }
    val fileLength = file.length()
    for (want in expected) {
      val got = header.tensors[want.name]
      if (got == null) {
        reasons.add("${file.name}: tensor '${want.name}' not found")
        continue
      }
      if (got.dtype != want.dtype) {
        reasons.add(
          "${file.name}: '${want.name}' dtype ${got.dtype}, expected ${want.dtype}",
        )
      }
      if (got.shape != want.shape) {
        reasons.add(
          "${file.name}: '${want.name}' shape ${got.shape}, expected ${want.shape}",
        )
      }
      if (header.dataStart + got.end > fileLength) {
        reasons.add(
          "${file.name}: '${want.name}' offsets exceed file size ($fileLength)",
        )
      }
    }
    return if (reasons.isEmpty()) CheckResult.Ok else CheckResult.Failed(reasons)
  }

  /** Parses the safetensors header; throws [IllegalArgumentException]. */
  fun parseHeader(file: File): ParsedHeader {
    require(file.isFile) { "Not a file: ${file.absolutePath}" }
    RandomAccessFile(file, "r").use { raf ->
      if (raf.length() < 8) {
        throw IllegalArgumentException("File too short for safetensors header")
      }
      val lenBytes = ByteArray(8)
      raf.readFully(lenBytes)
      val headerLen = ByteBuffer.wrap(lenBytes).order(ByteOrder.LITTLE_ENDIAN).long
      require(headerLen in 1..MAX_HEADER_BYTES) {
        "Implausible header length: $headerLen"
      }
      require(8 + headerLen <= raf.length()) {
        "Truncated safetensors header"
      }
      val jsonBytes = ByteArray(headerLen.toInt())
      raf.readFully(jsonBytes)
      val decoded = MiniJson.asObject(
        MiniJson.parse(String(jsonBytes, Charsets.UTF_8)),
        "safetensors header",
      )
      val tensors = LinkedHashMap<String, TensorLayout>()
      for ((name, raw) in decoded) {
        if (name == "__metadata__") continue
        val entry = MiniJson.asObject(raw, "tensor '$name'")
        val dtype = MiniJson.asString(entry["dtype"], "tensor '$name' dtype")
        val shape = MiniJson.asIntList(entry["shape"], "tensor '$name' shape")
        val offsets = MiniJson.asIntList(entry["data_offsets"], "tensor '$name' offsets")
        require(offsets.size == 2) { "Bad data_offsets for tensor '$name'" }
        val bpe = BYTES_PER_ELEMENT[dtype]
          ?: throw IllegalArgumentException("Unknown dtype '$dtype' for tensor '$name'")
        val start = offsets[0].toLong()
        val end = offsets[1].toLong()
        require(start >= 0 && end >= start) {
          "Bad data_offsets for tensor '$name'"
        }
        val elements = if (shape.isEmpty()) 1L else shape.fold(1L) { a, b -> a * b }
        require(end - start == elements * bpe) {
          "Size mismatch for tensor '$name': offsets say ${end - start} " +
            "bytes but $dtype$shape needs ${elements * bpe}"
        }
        tensors[name] = TensorLayout(dtype, shape, start, end)
      }
      return ParsedHeader(tensors, 8 + headerLen)
    }
  }
}
