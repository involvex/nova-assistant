package dev.nova.assistant

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Loads the learned DiT pad tokens from `pad_tokens.safetensors`.
 *
 * Z-Image pads caption (and image) sequences to a multiple of 32 with a
 * **learned** vector that remains real attention context — not a repeat of
 * the last real row (see `docs/z-image-turbo-litert.md` and the Core AI /
 * MLX ports). Shape is `[3840]` or `[1,3840]` (model dim); dtype BF16 or F32.
 */
object PadTokensLoader {
  data class PadTokens(
    val capPadToken: FloatArray,
    val xPadToken: FloatArray,
  ) {
    init {
      require(capPadToken.size == ZImageHostLoop.MODEL_DIM) {
        "cap_pad_token must be [${ZImageHostLoop.MODEL_DIM}], got ${capPadToken.size}"
      }
      require(xPadToken.size == ZImageHostLoop.MODEL_DIM) {
        "x_pad_token must be [${ZImageHostLoop.MODEL_DIM}], got ${xPadToken.size}"
      }
    }
  }

  fun load(padTokensFile: File): PadTokens {
    val header = SafetensorsHeaderCheck.parseHeader(padTokensFile)
    return PadTokens(
      capPadToken = readVector(header, padTokensFile, "cap_pad_token"),
      xPadToken = readVector(header, padTokensFile, "x_pad_token"),
    )
  }

  private fun readVector(
    header: SafetensorsHeaderCheck.ParsedHeader,
    file: File,
    name: String,
  ): FloatArray {
    val entry = header.tensors[name]
      ?: throw IllegalStateException("'$name' not found in ${file.absolutePath}")
    val count = entry.shape.fold(1) { a, b -> a * b }
    require(count == ZImageHostLoop.MODEL_DIM) {
      "'$name' must have ${ZImageHostLoop.MODEL_DIM} elements, got shape ${entry.shape}"
    }
    val bpe = SafetensorsHeaderCheck.BYTES_PER_ELEMENT[entry.dtype]
      ?: throw IllegalStateException("Unknown dtype ${entry.dtype} for '$name'")
    val bytes = ByteArray(count * bpe)
    RandomAccessFile(file, "r").use { raf ->
      raf.seek(header.dataStart + entry.start)
      raf.readFully(bytes)
    }
    return when (entry.dtype) {
      "F32" -> {
        val out = FloatArray(count)
        ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer().get(out)
        out
      }
      "BF16" -> FloatArray(count) { i ->
        val lo = bytes[i * 2].toInt() and 0xFF
        val hi = bytes[i * 2 + 1].toInt() and 0xFF
        ZImageEmbedLookup.bf16ToFloat32(hi shl 8 or lo)
      }
      else -> throw IllegalStateException("'$name' must be F32 or BF16, got ${entry.dtype}")
    }
  }
}
