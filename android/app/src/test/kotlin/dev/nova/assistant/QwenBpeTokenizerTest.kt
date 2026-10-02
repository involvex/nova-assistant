package dev.nova.assistant

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.Rule
import java.io.File

/**
 * Byte-level BPE against tiny synthetic `vocab.json` / `merges.txt` pairs.
 * `Ġ` is U+0120, the GPT-2 byte-alphabet space.
 */
class QwenBpeTokenizerTest {
  @get:Rule
  val temp = TemporaryFolder()

  private fun writeTokenizer(
    vocabJson: String,
    merges: String,
  ): File {
    val dir = temp.newFolder("tokenizer")
    File(dir, "vocab.json").writeText(vocabJson, Charsets.UTF_8)
    File(dir, "merges.txt").writeText(merges, Charsets.UTF_8)
    return dir
  }

  private fun baseDir(): File = writeTokenizer(
    "{\"a\":0,\"b\":1,\"ab\":2,\"Ġ\":3,\"Ġa\":4,\"c\":5,\"abc\":6}",
    "#version: 0.2\na b\nĠ a\nab c\n",
  )

  @Test
  fun `single merge resolves to one id`() {
    val tok = QwenBpeTokenizer.load(baseDir())
    assertArrayEquals(intArrayOf(2), tok.encode("ab"))
  }

  @Test
  fun `space-prefixed piece keeps byte alphabet without merge`() {
    // "a b" → "a" + " b"; ("Ġ",b) is unranked so the space stays split.
    val tok = QwenBpeTokenizer.load(baseDir())
    assertArrayEquals(intArrayOf(0, 3, 1), tok.encode("a b"))
  }

  @Test
  fun `merge rank order chains left to right`() {
    // "abc" → (a,b) rank 0 first, then (ab,c) rank 2.
    val tok = QwenBpeTokenizer.load(baseDir())
    assertArrayEquals(intArrayOf(6), tok.encode("abc"))
  }

  @Test
  fun `empty input encodes to empty`() {
    val tok = QwenBpeTokenizer.load(baseDir())
    assertEquals(0, tok.encode("").size)
    assertEquals(7, tok.vocabSize)
  }

  @Test(expected = IllegalStateException::class)
  fun `byte missing from vocab fails loudly`() {
    val dir = writeTokenizer("{\"a\":0}", "#version: 0.2\n")
    QwenBpeTokenizer.load(dir).encode("b")
  }

  @Test(expected = IllegalArgumentException::class)
  fun `missing merges file fails loudly`() {
    val dir = temp.newFolder("broken")
    File(dir, "vocab.json").writeText("{\"a\":0}", Charsets.UTF_8)
    QwenBpeTokenizer.load(dir)
  }

  @Test
  fun `multibyte input round-trips through bytes`() {
    // "é" is 2 UTF-8 bytes; both must be in the vocab for byte fallback.
    val dir = writeTokenizer(
      "{\"Ã\":10,\"©\":11}",
      "#version: 0.2\n",
    )
    val tok = QwenBpeTokenizer.load(dir)
    // U+00E9 → UTF-8 [0xC3, 0xA9] → GPT-2 byte chars Ã (U+00C3), © (U+00A9).
    assertArrayEquals(intArrayOf(10, 11), tok.encode("é"))
    assertTrue(tok.vocabSize == 2)
  }
}
