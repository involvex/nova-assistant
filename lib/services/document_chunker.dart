class DocumentChunker {
  /// Split [text] into chunks of at most [maxChunkSize] characters,
  /// with [overlap] characters of overlap between consecutive chunks.
  /// Chunks are split at paragraph or sentence boundaries when possible.
  static List<String> chunk(
    String text, {
    int maxChunkSize = 2000,
    int overlap = 200,
  }) {
    if (text.length <= maxChunkSize) return [text];

    final chunks = <String>[];
    int start = 0;

    while (start < text.length) {
      int end = start + maxChunkSize;
      if (end >= text.length) {
        chunks.add(text.substring(start).trim());
        break;
      }

      // Try to break at paragraph boundary
      final lastNewline = text.lastIndexOf('\n\n', end);
      if (lastNewline > start + maxChunkSize ~/ 2) {
        end = lastNewline + 2;
      } else {
        // Try to break at sentence boundary
        final lastSentence = text.lastIndexOf(RegExp(r'[.!?]\s'), end);
        if (lastSentence > start + maxChunkSize ~/ 2) {
          end = lastSentence + 2;
        } else {
          // Try line break
          final lastLine = text.lastIndexOf('\n', end);
          if (lastLine > start + maxChunkSize ~/ 2) {
            end = lastLine + 1;
          }
        }
      }

      chunks.add(text.substring(start, end).trim());
      start = end - overlap;
      if (start < 0) start = 0;
    }

    return chunks.where((c) => c.isNotEmpty).toList();
  }

  /// Find the most relevant chunks for a given [query] using keyword matching.
  /// Returns chunks sorted by relevance score, up to [maxChunks].
  static List<String> findRelevant(
    String text,
    String query, {
    int maxChunks = 3,
    int maxChunkSize = 2000,
  }) {
    final chunks = chunk(text, maxChunkSize: maxChunkSize);
    if (chunks.isEmpty) return [];

    final queryWords = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toSet();

    if (queryWords.isEmpty) return chunks.take(maxChunks).toList();

    final scored = chunks.map((chunk) {
      final chunkLower = chunk.toLowerCase();
      var matches = 0;
      for (final word in queryWords) {
        if (chunkLower.contains(word)) matches++;
      }
      final score = matches / queryWords.length;
      return MapEntry(chunk, score);
    }).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return scored
        .take(maxChunks)
        .where((s) => s.value > 0)
        .map((s) => s.key)
        .toList();
  }
}
