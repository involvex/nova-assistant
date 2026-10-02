package dev.nova.assistant

/**
 * Minimal dependency-free JSON parser.
 *
 * Pure JVM (no Android, no org.json) so host-side asset manifests
 * (`vocab.json`, safetensors headers) parse identically in unit tests and
 * on-device. Supports objects, arrays, strings (all escapes incl. \uXXXX),
 * numbers (Long when integral, Double otherwise), true/false/null.
 * Throws [IllegalArgumentException] on malformed input.
 */
internal object MiniJson {
  fun parse(text: String): Any? {
    val parser = Parser(text)
    val value = parser.parseValue()
    parser.skipWhitespace()
    require(parser.atEnd()) { "Trailing characters after JSON value" }
    return value
  }

  @Suppress("UNCHECKED_CAST")
  fun asObject(value: Any?, what: String): Map<String, Any?> {
    require(value is Map<*, *>) { "$what must be a JSON object" }
    return value as Map<String, Any?>
  }

  fun asString(value: Any?, what: String): String {
    require(value is String) { "$what must be a JSON string" }
    return value
  }

  fun asIntList(value: Any?, what: String): List<Int> {
    require(value is List<*>) { "$what must be a JSON array" }
    return value.map {
      when (it) {
        is Long -> it.toInt()
        is Int -> it
        is Double -> it.toInt()
        else -> throw IllegalArgumentException("$what must be an int array")
      }
    }
  }

  private class Parser(val text: String) {
    var pos = 0

    fun atEnd(): Boolean = pos >= text.length

    fun skipWhitespace() {
      while (pos < text.length && text[pos].isWhitespace()) pos++
    }

    fun parseValue(): Any? {
      skipWhitespace()
      require(pos < text.length) { "Unexpected end of JSON" }
      return when (val c = text[pos]) {
        '{' -> parseObject()
        '[' -> parseArray()
        '"' -> parseString()
        't' -> expectLiteral("true", true)
        'f' -> expectLiteral("false", false)
        'n' -> expectLiteral("null", null)
        else -> {
          require(c == '-' || c.isDigit()) { "Unexpected character '$c' at $pos" }
          parseNumber()
        }
      }
    }

    private fun expectLiteral(literal: String, value: Any?): Any? {
      require(text.startsWith(literal, pos)) { "Invalid literal at $pos" }
      pos += literal.length
      return value
    }

    private fun parseObject(): Map<String, Any?> {
      pos++ // {
      val map = LinkedHashMap<String, Any?>()
      skipWhitespace()
      if (pos < text.length && text[pos] == '}') {
        pos++
        return map
      }
      while (true) {
        skipWhitespace()
        require(pos < text.length && text[pos] == '"') { "Expected string key at $pos" }
        val key = parseString()
        skipWhitespace()
        require(pos < text.length && text[pos] == ':') { "Expected ':' at $pos" }
        pos++
        map[key] = parseValue()
        skipWhitespace()
        require(pos < text.length) { "Unterminated object" }
        when (text[pos]) {
          ',' -> pos++
          '}' -> {
            pos++
            return map
          }
          else -> throw IllegalArgumentException("Expected ',' or '}' at $pos")
        }
      }
    }

    private fun parseArray(): List<Any?> {
      pos++ // [
      val list = ArrayList<Any?>()
      skipWhitespace()
      if (pos < text.length && text[pos] == ']') {
        pos++
        return list
      }
      while (true) {
        list.add(parseValue())
        skipWhitespace()
        require(pos < text.length) { "Unterminated array" }
        when (text[pos]) {
          ',' -> pos++
          ']' -> {
            pos++
            return list
          }
          else -> throw IllegalArgumentException("Expected ',' or ']' at $pos")
        }
      }
    }

    private fun parseString(): String {
      pos++ // opening quote
      val sb = StringBuilder()
      while (true) {
        require(pos < text.length) { "Unterminated string" }
        val c = text[pos++]
        when (c) {
          '"' -> return sb.toString()
          '\\' -> {
            require(pos < text.length) { "Unterminated escape" }
            when (val e = text[pos++]) {
              '"', '\\', '/' -> sb.append(e)
              'b' -> sb.append('\b')
              'f' -> sb.append('\u000C')
              'n' -> sb.append('\n')
              'r' -> sb.append('\r')
              't' -> sb.append('\t')
              'u' -> {
                require(pos + 4 <= text.length) { "Bad \\u escape at $pos" }
                val hex = text.substring(pos, pos + 4)
                sb.append(hex.toInt(16).toChar())
                pos += 4
              }
              else -> throw IllegalArgumentException("Bad escape '\\$e' at $pos")
            }
          }
          else -> {
            require(c >= ' ') { "Unescaped control character in string" }
            sb.append(c)
          }
        }
      }
    }

    private fun parseNumber(): Number {
      val start = pos
      if (pos < text.length && text[pos] == '-') pos++
      while (pos < text.length && text[pos].isDigit()) pos++
      var isDouble = false
      if (pos < text.length && text[pos] == '.') {
        isDouble = true
        pos++
        while (pos < text.length && text[pos].isDigit()) pos++
      }
      if (pos < text.length && (text[pos] == 'e' || text[pos] == 'E')) {
        isDouble = true
        pos++
        if (pos < text.length && (text[pos] == '+' || text[pos] == '-')) pos++
        while (pos < text.length && text[pos].isDigit()) pos++
      }
      val raw = text.substring(start, pos)
      return if (isDouble) raw.toDouble() else raw.toLong()
    }
  }
}
