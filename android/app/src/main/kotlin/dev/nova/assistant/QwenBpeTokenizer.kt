package dev.nova.assistant

import java.io.File
import java.util.regex.Pattern

/**
 * Byte-level BPE tokenizer for the Qwen3 text encoder (`Z-Image Turbo`).
 *
 * Pure JVM (no Android imports) so encoding is unit-testable. Qwen3 uses the
 * GPT-2 byte-level BPE family (vocab 151936, byte fallback): `vocab.json`
 * maps token spellings to ids and `merges.txt` ranks the merges. Encoding is
 * `pretokenize → UTF-8 bytes → byte alphabet → BPE merges → vocab ids`.
 *
 * Staged assets (downloaded by Dart into `<modelDir>/tokenizer/`):
 * `vocab.json`, `merges.txt` (+ `tokenizer.json`, `tokenizer_config.json`
 * kept for provenance; this loader does not need them).
 */
class QwenBpeTokenizer private constructor(
  private val encoder: Map<String, Int>,
  private val bpeRanks: Map<Pair<String, String>, Int>,
) {
  val vocabSize: Int get() = encoder.size

  private val cache = HashMap<String, List<String>>()

  /**
   * Encodes [text] to vocabulary ids. Every byte-level piece must resolve —
   * a missing entry means the staged `vocab.json` does not cover the byte
   * alphabet and the download is corrupt or mismatched.
   */
  fun encode(text: String): IntArray {
    if (text.isEmpty()) return IntArray(0)
    val out = ArrayList<Int>()
    val matcher = PRETOKENIZER.matcher(text)
    while (matcher.find()) {
      val piece = matcher.group()
      // UTF-8 bytes → byte-alphabet chars FIRST (GPT-2 order): even a
      // single-char piece like "é" is two bytes and must be split.
      val bytes = piece.toByteArray(Charsets.UTF_8).map { byteToUnicode(it) }
      val cacheKey = bytes.joinToString("")
      val bpeTokens = cache.getOrPut(cacheKey) { bpeSplit(bytes) }
      for (token in bpeTokens) {
        out.add(
          encoder[token]
            ?: throw IllegalStateException("Token '$token' missing from vocab.json"),
        )
      }
    }
    return out.toIntArray()
  }

  /** BPE merge loop over an already byte-split pre-token. */
  private fun bpeSplit(split: List<String>): List<String> {
    var word = split
    if (word.size <= 1) return word
    var pairs = getPairs(word)
    if (pairs.isEmpty()) return word
    while (true) {
      val bigram = pairs.minByOrNull { bpeRanks[it] ?: Int.MAX_VALUE }
        ?: break
      if (!bpeRanks.containsKey(bigram)) break
      val (first, second) = bigram
      val merged = first + second
      val newWord = ArrayList<String>()
      var i = 0
      while (i < word.size) {
        var j = i
        while (j < word.size && word[j] != first) j++
        if (j >= word.size) {
          newWord.addAll(word.subList(i, word.size))
          break
        }
        newWord.addAll(word.subList(i, j))
        i = j
        if (word[i] == first && i < word.size - 1 && word[i + 1] == second) {
          newWord.add(merged)
          i += 2
        } else {
          newWord.add(word[i])
          i += 1
        }
      }
      word = newWord
      if (word.size == 1) break
      pairs = getPairs(word)
    }
    return word
  }

  companion object {
    /**
     * GPT-2/Qwen byte-level split: contractions, letter/number runs with an
     * optional leading space, symbol runs, and whitespace. `\p{L}`/`\p{N}`
     * are Unicode-aware in Java by default.
     */
    private val PRETOKENIZER: Pattern = Pattern.compile(
      "'s|'t|'re|'ve|'m|'ll|'d| ?\\p{L}+| ?\\p{N}+| ?[^\\s\\p{L}\\p{N}]+|\\s+(?!\\S)|\\s+",
    )

    private const val MAX_VOCAB_BYTES = 64 * 1024 * 1024
    private const val MAX_MERGES_BYTES = 32 * 1024 * 1024

    /** Loads `vocab.json` + `merges.txt` from a staged `tokenizer/` dir. */
    fun load(tokenizerDir: File): QwenBpeTokenizer {
      val vocabFile = File(tokenizerDir, "vocab.json")
      val mergesFile = File(tokenizerDir, "merges.txt")
      require(vocabFile.isFile) { "Missing tokenizer file: ${vocabFile.absolutePath}" }
      require(mergesFile.isFile) { "Missing tokenizer file: ${mergesFile.absolutePath}" }
      require(vocabFile.length() in 1..MAX_VOCAB_BYTES) {
        "Implausible vocab.json size: ${vocabFile.length()}"
      }
      require(mergesFile.length() in 1..MAX_MERGES_BYTES) {
        "Implausible merges.txt size: ${mergesFile.length()}"
      }

      val decoded = MiniJson.parse(vocabFile.readText(Charsets.UTF_8))
      val obj = MiniJson.asObject(decoded, "vocab.json")
      val encoder = HashMap<String, Int>(obj.size)
      obj.forEach { (key, value) ->
        require(value is Long || value is Int || value is Double) {
          "vocab.json id for '$key' is not a number"
        }
        val id = when (value) {
          is Long -> value.toInt()
          is Int -> value
          else -> (value as Double).toInt()
        }
        require(id >= 0) { "vocab.json id for '$key' is negative" }
        encoder[key] = id
      }
      require(encoder.isNotEmpty()) { "vocab.json is empty" }

      val ranks = HashMap<Pair<String, String>, Int>()
      var rank = 0
      mergesFile.forEachLine(Charsets.UTF_8) { line ->
        val trimmed = line.trim()
        if (trimmed.isEmpty() || trimmed.startsWith("#version")) return@forEachLine
        val space = trimmed.indexOf(' ')
        require(space > 0 && space < trimmed.length - 1) {
          "Malformed merges.txt line: '$trimmed'"
        }
        val first = trimmed.substring(0, space)
        val second = trimmed.substring(space + 1)
        ranks.putIfAbsent(first to second, rank++)
      }

      return QwenBpeTokenizer(encoder, ranks)
    }

    // ---------------------------------------------------------- byte alphabet

    private val byteToChar: CharArray by lazy {
      val bs = ArrayList<Int>()
      bs.addAll(33..126)
      bs.addAll(161..172)
      bs.addAll(174..255)
      val cs = ArrayList<Int>(bs)
      var n = 0
      for (b in 0..255) {
        if (!bs.contains(b)) {
          bs.add(b)
          cs.add(256 + n)
          n++
        }
      }
      CharArray(256) { i -> cs[bs.indexOf(i)].toChar() }
    }

    private fun byteToUnicode(byte: Byte): String {
      val c = byteToChar[byte.toInt() and 0xFF]
      return c.toString()
    }

    private fun getPairs(word: List<String>): Set<Pair<String, String>> {
      val pairs = LinkedHashSet<Pair<String, String>>()
      var prev = word[0]
      for (i in 1 until word.size) {
        pairs.add(prev to word[i])
        prev = word[i]
      }
      return pairs
    }
  }
}
