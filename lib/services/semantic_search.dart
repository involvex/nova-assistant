import 'dart:math' as math;

/// TF-IDF based semantic search for conversation memory.
///
/// Replaces simple keyword overlap with term frequency–inverse document
/// frequency scoring so that rare, distinctive words carry more weight
/// than common stop words.
class SemanticSearch {
  /// Stop words that carry little semantic meaning.
  static const _stopWords = {
    'a',
    'an',
    'the',
    'is',
    'it',
    'to',
    'in',
    'of',
    'and',
    'or',
    'for',
    'on',
    'at',
    'by',
    'with',
    'from',
    'as',
    'this',
    'that',
    'was',
    'are',
    'be',
    'has',
    'had',
    'have',
    'do',
    'does',
    'did',
    'but',
    'not',
    'if',
    'so',
    'no',
    'yes',
    'can',
    'may',
    'will',
    'just',
    'than',
    'then',
    'what',
    'when',
    'where',
    'how',
    'who',
    'which',
    'there',
    'their',
    'they',
    'them',
    'he',
    'she',
    'we',
    'you',
    'me',
    'my',
    'your',
    'his',
    'her',
    'our',
    'its',
    'i',
    'am',
    'been',
    'being',
    'about',
    'into',
    'over',
    'after',
    'before',
    'between',
    'under',
    'again',
    'once',
    'here',
    'very',
    'some',
    'more',
    'most',
    'other',
    'such',
    'only',
  };

  /// Tokenize text into lowercase words, stripping non-alphanumeric chars.
  static List<String> tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && !_stopWords.contains(w))
        .toList();
  }

  /// Compute term frequency for a list of tokens.
  ///
  /// Returns a map from term to its normalized frequency (count / total).
  static Map<String, double> termFrequency(List<String> tokens) {
    if (tokens.isEmpty) return {};
    final counts = <String, int>{};
    for (final t in tokens) {
      counts[t] = (counts[t] ?? 0) + 1;
    }
    final total = tokens.length.toDouble();
    return counts.map((k, v) => MapEntry(k, v / total));
  }

  /// Compute inverse document frequency for terms across documents.
  ///
  /// [documents] is a list of token lists, one per document.
  /// Returns a map from term to IDF score: log(N / df) where N = total docs,
  /// df = docs containing the term.
  static Map<String, double> inverseDocumentFrequency(
    List<List<String>> documents,
  ) {
    final n = documents.length.toDouble();
    if (n == 0) return {};

    final docFreq = <String, int>{};
    for (final doc in documents) {
      final unique = doc.toSet();
      for (final term in unique) {
        docFreq[term] = (docFreq[term] ?? 0) + 1;
      }
    }

    return docFreq.map((term, df) {
      // Add 1 to df to avoid log(0) and soften the curve for small corpora
      final idf = math.log((n + 1) / (df + 1)) + 1;
      return MapEntry(term, idf);
    });
  }

  /// Score a query against a single document using TF-IDF.
  ///
  /// [queryTokens] — pre-tokenized query.
  /// [docTokens] — pre-tokenized document.
  /// [idf] — precomputed IDF map from the corpus.
  static double scoreDocument(
    List<String> queryTokens,
    List<String> docTokens,
    Map<String, double> idf,
  ) {
    if (queryTokens.isEmpty || docTokens.isEmpty) return 0;

    final docTf = termFrequency(docTokens);
    double score = 0;

    for (final term in queryTokens) {
      final tf = docTf[term] ?? 0;
      final idfScore = idf[term] ?? 1;
      score += tf * idfScore;
    }

    return score;
  }

  /// Rank documents by relevance to the query.
  ///
  /// Each entry in [documents] is a list of tokens representing one document.
  /// Returns indices sorted by descending score, along with their scores.
  ///
  /// If [idf] is provided, it will be used instead of computing it fresh,
  /// which is useful when searching the same corpus multiple times.
  static List<ScoredEntry> search({
    required List<String> queryTokens,
    required List<List<String>> documents,
    int topK = 5,
    double minScore = 0,
    Map<String, double>? idf,
  }) {
    if (queryTokens.isEmpty || documents.isEmpty) return [];

    final actualIdf = idf ?? inverseDocumentFrequency(documents);

    final scored = <ScoredEntry>[];
    for (var i = 0; i < documents.length; i++) {
      final s = scoreDocument(queryTokens, documents[i], actualIdf);
      if (s > minScore) {
        scored.add(ScoredEntry(index: i, score: s));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(topK).toList();
  }
}

/// A search result with an index into the original list and a relevance score.
class ScoredEntry {
  final int index;
  final double score;

  const ScoredEntry({required this.index, required this.score});

  @override
  String toString() =>
      'ScoredEntry(index: $index, score: ${score.toStringAsFixed(3)})';
}
