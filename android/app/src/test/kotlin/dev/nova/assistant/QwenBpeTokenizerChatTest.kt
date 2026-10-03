package dev.nova.assistant

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/**
 * `encodeChatPrompt` against a synthetic vocab rather than the real 151k Qwen
 * one. Z-Image's text encoder only sees correctly-conditioned text when the
 * prompt is wrapped in the chat template it was trained with, so the wrapper
 * has to splice the special tokens in as ids — the GPT-2 pre-tokenizer would
 * otherwise split `<|im_start|>` into `<`, `|`, `im`, `_start`, `|`.
 */
class QwenBpeTokenizerChatTest {
  @get:Rule
  val temp = TemporaryFolder()

  /**
   * No merges at all, so every byte-level piece becomes its own id.
   *
   * The keys come from the tokenizer's own byte-alphabet mapping rather than
   * from reading the source text: byte-level BPE rewrites each byte to a
   * distinct Unicode char (byte 32 is U+0120, byte 10 is U+010A), so a
   * hand-written alphabet silently misses entries.
   */
  private fun chatDir(vararg texts: String): File {
    val dir = temp.newFolder("tokenizer")
    val keys = texts.flatMap { QwenBpeTokenizer.byteLevelKeys(it) }
      .distinct()
      .sorted()
    val vocab = keys
      .mapIndexed { i, key -> "\"" + key.escapeJson() + "\":" + i }
      .joinToString(",")
    File(dir, "vocab.json").writeText("{$vocab}", Charsets.UTF_8)
    File(dir, "merges.txt").writeText("#version: 0.2\n", Charsets.UTF_8)
    return dir
  }

  /** JSON string escapes for the control characters the byte alphabet yields. */
  private fun String.escapeJson(): String {
    val out = StringBuilder()
    for (ch in this) {
      when {
        ch == '"' -> out.append("\\\"")
        ch == '\\' -> out.append("\\\\")
        ch.code < 0x20 -> out.append("\\u").append(ch.code.toString(16).padStart(4, '0'))
        else -> out.append(ch)
      }
    }
    return out.toString()
  }

  private fun IntArray.containsSub(needle: IntArray): Boolean {
    if (needle.isEmpty() || needle.size > size) return false
    outer@ for (start in 0..(size - needle.size)) {
      for (i in needle.indices) if (this[start + i] != needle[i]) continue@outer
      return true
    }
    return false
  }

  private val scaffolding = arrayOf("user\n", "\n", "assistant\n", "a cat")

  @Test
  fun `chat prompt wraps the text and splices special tokens as ids`() {
    val tok = QwenBpeTokenizer.load(chatDir(*scaffolding))
    val ids = tok.encodeChatPrompt("a cat")

    // Two im_start markers (the open turn and the generation prompt) and one
    // im_end, in that order. Fixed offsets are avoided because the
    // trailing "assistant\n" expands to one id per byte in this merge-free vocab.
    assertEquals(IM_START, ids.first())
    assertEquals(2, ids.count { it == IM_START })
    assertEquals(1, ids.count { it == IM_END })
    assertTrue(ids.indexOf(IM_START) < ids.indexOf(IM_END))

    // The prompt and both scaffolding pieces survive verbatim.
    assertTrue(ids.containsSub(tok.encode("a cat")))
    assertTrue(ids.containsSub(tok.encode("user\n")))
    assertTrue(ids.containsSub(tok.encode("assistant\n")))
  }

  @Test
  fun `raw encode is not templated`() {
    // The bug being fixed: a bare prompt reaches the encoder with no chat
    // scaffolding, which is out of distribution for this checkpoint.
    val tok = QwenBpeTokenizer.load(chatDir(*scaffolding))
    assertFalse(tok.encode("a cat").contains(151644))
    assertFalse(tok.encode("a cat").contains(151645))
  }

  @Test
  fun `chat prompt of empty text still carries the template`() {
    // The CFG uncond branch passes "", but it must still be templated.
    val tok = QwenBpeTokenizer.load(chatDir(*scaffolding))
    val ids = tok.encodeChatPrompt("")
    assertTrue(ids.isNotEmpty())
    assertEquals(151644, ids.first())
    assertTrue(ids.contains(151645))
  }

  @Test
  fun `chat prompt is deterministic`() {
    val tok = QwenBpeTokenizer.load(chatDir(*scaffolding))
    assertArrayEquals(
      tok.encodeChatPrompt("a cat"),
      tok.encodeChatPrompt("a cat"),
    )
  }
}
