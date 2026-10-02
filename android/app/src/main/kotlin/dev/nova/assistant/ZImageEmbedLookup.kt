package dev.nova.assistant

import java.io.File
import java.io.RandomAccessFile

/**
 * Turns prompt token ids into `qwen_enc` inputs via the extracted
 * `embed_tokens` matrix.
 *
 * Pure JVM (no Android imports). Reads only the referenced rows through
 * positional I/O — the 778 MB matrix is never fully mapped, which matters
 * because a blind 778 MB mmap is an uncatchable OOM/LMK risk on phones.
 * Call [SafetensorsHeaderCheck.checkDerivedAssets] first; these helpers
 * assume the header already proved the layout.
 */
object ZImageEmbedLookup {
  const val EMBED_DIM = 2560
  const val EMBED_TOKENS = 151936
  const val ENCODER_SEQUENCE_TOKENS = 64

  /**
   * Full prompt path: tokenize [prompt] with the staged Qwen3 BPE files,
   * gather the rows, left-pad to `[1,64,2560]`. `qwen_enc` is causal, so
   * left padding keeps real tokens at their trained positions (see
   * `docs/z-image-turbo-litert.md`).
   */
  fun prepareInputsEmbeds(prompt: String, modelDir: File): FloatArray {
    val tokenizer = QwenBpeTokenizer.load(File(modelDir, "tokenizer"))
    val ids = tokenizer.encode(prompt)
    return inputsEmbeds(ids, File(modelDir, "embed_tokens.safetensors"))
  }

  /**
   * Gathers [ids] rows and left-pads with zeros to `[seqLen, dim]`
   * row-major. Keeps the last [seqLen] ids when the prompt is longer —
   * causal encoders degrade least when the tail survives.
   */
  fun inputsEmbeds(
    ids: IntArray,
    embedFile: File,
    dim: Int = EMBED_DIM,
    seqLen: Int = ENCODER_SEQUENCE_TOKENS,
  ): FloatArray {
    val kept = if (ids.size > seqLen) ids.copyOfRange(ids.size - seqLen, ids.size) else ids
    val rows = gatherRows(embedFile, kept, dim)
    val out = FloatArray(seqLen * dim)
    val padRows = seqLen - kept.size
    System.arraycopy(rows, 0, out, padRows * dim, rows.size)
    return out
  }

  /** Gathers one float32 row per id, in order. */
  fun gatherRows(embedFile: File, ids: IntArray, dim: Int = EMBED_DIM): FloatArray {
    require(ids.isNotEmpty()) { "No token ids to embed" }
    val header = SafetensorsHeaderCheck.parseHeader(embedFile)
    val entry = header.tensors["embed_tokens"]
      ?: throw IllegalStateException("embed_tokens not found in ${embedFile.absolutePath}")
    val rows = entry.shape.getOrElse(0) { 0 }
    val cols = entry.shape.getOrElse(1) { 0 }
    require(cols == dim) {
      "embed_tokens width $cols != expected $dim in ${embedFile.absolutePath}"
    }
    val bpe = SafetensorsHeaderCheck.BYTES_PER_ELEMENT[entry.dtype]
      ?: throw IllegalStateException("Unknown dtype ${entry.dtype}")
    require(bpe == 2) {
      "embed_tokens must be a 2-byte dtype (BF16/F16), got ${entry.dtype}"
    }

    val out = FloatArray(ids.size * dim)
    RandomAccessFile(embedFile, "r").use { raf ->
      val rowBytes = ByteArray(dim * bpe)
      for ((row, id) in ids.withIndex()) {
        require(id in 0 until rows) {
          "Token id $id out of range [0,$rows) for ${embedFile.absolutePath}"
        }
        raf.seek(header.dataStart + entry.start + id.toLong() * dim * bpe)
        raf.readFully(rowBytes)
        val base = row * dim
        for (c in 0 until dim) {
          val lo = rowBytes[c * 2].toInt() and 0xFF
          val hi = rowBytes[c * 2 + 1].toInt() and 0xFF
          out[base + c] = bf16ToFloat32(hi shl 8 or lo)
        }
      }
    }
    return out
  }

  /**
   * BF16 bits → float32. Exponent is copied; mantissa is shifted into place
   * (BF16 has no subnormal subtlety beyond what float32 already models).
   * NaN payloads collapse to quiet NaN, infinities round-trip.
   */
  fun bf16ToFloat32(bits: Int): Float {
    val b = bits and 0xFFFF
    val sign = b ushr 15
    val exp = (b ushr 7) and 0xFF
    val mant = b and 0x7F
    val fbits = if (exp == 0xFF) {
      // Inf/NaN: keep the class, force quiet NaN for any payload.
      (sign shl 31) or (0xFF shl 23) or (if (mant == 0) 0 else (1 shl 22))
    } else {
      (sign shl 31) or (exp shl 23) or (mant shl 16)
    }
    return Float.fromBits(fbits)
  }
}
