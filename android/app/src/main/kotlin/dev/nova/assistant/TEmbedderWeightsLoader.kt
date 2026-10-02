package dev.nova.assistant

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Loads `TimestepEmbedder` MLP weights from the extracted
 * `t_embedder.safetensors` (~2 MB) into [ZImageHostLoop.TimestepEmbedderWeights].
 *
 * Pure JVM (no Android imports). Assumes [SafetensorsHeaderCheck] already
 * proved the layout; this only does the typed read. Sizes are enforced by
 * the [ZImageHostLoop.TimestepEmbedderWeights] constructor.
 */
object TEmbedderWeightsLoader {
  fun load(tEmbedderFile: File): ZImageHostLoop.TimestepEmbedderWeights {
    val header = SafetensorsHeaderCheck.parseHeader(tEmbedderFile)
    fun read(name: String): FloatArray {
      val entry = header.tensors[name]
        ?: throw IllegalStateException("'$name' not found in ${tEmbedderFile.absolutePath}")
      require(entry.dtype == "F32") {
        "'$name' must be F32, got ${entry.dtype}"
      }
      val count = entry.shape.fold(1) { a, b -> a * b }
      val bytes = ByteArray(count * 4)
      RandomAccessFile(tEmbedderFile, "r").use { raf ->
        raf.seek(header.dataStart + entry.start)
        raf.readFully(bytes)
      }
      val floats = FloatArray(count)
      ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer().get(floats)
      return floats
    }
    return ZImageHostLoop.TimestepEmbedderWeights(
      mlp0Weight = read("t_embedder.mlp.0.weight"),
      mlp0Bias = read("t_embedder.mlp.0.bias"),
      mlp2Weight = read("t_embedder.mlp.2.weight"),
      mlp2Bias = read("t_embedder.mlp.2.bias"),
    )
  }
}
