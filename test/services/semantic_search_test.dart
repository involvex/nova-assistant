import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/services/semantic_search.dart';

void main() {
  group('SemanticSearch.tokenize', () {
    test('lowercases and strips punctuation', () {
      final tokens = SemanticSearch.tokenize('Hello, World! 123');
      expect(tokens, ['hello', 'world', '123']);
    });

    test('removes stop words', () {
      final tokens = SemanticSearch.tokenize(
        'the quick brown fox jumps over the lazy dog',
      );
      expect(tokens,
          containsAll(['quick', 'brown', 'fox', 'jumps', 'lazy', 'dog']));
      expect(tokens, isNot(contains('the')));
      expect(tokens, isNot(contains('over')));
    });

    test('returns empty list for empty input', () {
      expect(SemanticSearch.tokenize(''), isEmpty);
    });

    test('returns empty list for only stop words', () {
      expect(SemanticSearch.tokenize('the is a an'), isEmpty);
    });
  });

  group('SemanticSearch.termFrequency', () {
    test('computes normalized frequencies', () {
      final tf = SemanticSearch.termFrequency(['a', 'b', 'a']);
      expect(tf['a'], closeTo(2 / 3, 0.001));
      expect(tf['b'], closeTo(1 / 3, 0.001));
    });

    test('returns empty map for empty tokens', () {
      expect(SemanticSearch.termFrequency([]), isEmpty);
    });
  });

  group('SemanticSearch.inverseDocumentFrequency', () {
    test('rare terms get higher IDF than common terms', () {
      final docs = [
        ['apple', 'banana'],
        ['apple', 'cherry'],
        ['apple', 'date'],
      ];
      final idf = SemanticSearch.inverseDocumentFrequency(docs);

      // apple appears in all 3 docs → lower IDF
      // banana appears in 1 doc → higher IDF
      expect(idf['banana']!, greaterThan(idf['apple']!));
    });

    test('handles empty corpus', () {
      expect(SemanticSearch.inverseDocumentFrequency([]), isEmpty);
    });
  });

  group('SemanticSearch.search', () {
    test('ranks documents with more relevant terms higher', () {
      final docs = [
        SemanticSearch.tokenize('the cat sat on the mat'),
        SemanticSearch.tokenize('a dog played with a ball'),
        SemanticSearch.tokenize('the cat played with a ball'),
      ];
      final query = SemanticSearch.tokenize('cat played');
      final results = SemanticSearch.search(
        queryTokens: query,
        documents: docs,
        topK: 3,
      );

      expect(results, isNotEmpty);
      // Doc 2 has both "cat" and "played" → should rank highest
      expect(results.first.index, 2);
    });

    test('returns empty for no matching terms', () {
      final docs = [
        SemanticSearch.tokenize('apple banana'),
      ];
      final query = SemanticSearch.tokenize('quantum physics');
      final results = SemanticSearch.search(
        queryTokens: query,
        documents: docs,
        topK: 3,
      );

      expect(results, isEmpty);
    });

    test('respects minScore threshold', () {
      final docs = [
        SemanticSearch.tokenize('hello world'),
      ];
      final query = SemanticSearch.tokenize('hello');
      final results = SemanticSearch.search(
        queryTokens: query,
        documents: docs,
        topK: 3,
        minScore: 999, // impossibly high
      );

      expect(results, isEmpty);
    });

    test('returns topK results only', () {
      final docs = List.generate(
        10,
        (_) => SemanticSearch.tokenize('the quick brown fox jumps'),
      );
      final query = SemanticSearch.tokenize('quick fox');
      final results = SemanticSearch.search(
        queryTokens: query,
        documents: docs,
        topK: 3,
      );

      expect(results.length, lessThanOrEqualTo(3));
    });

    test('scores unique terms higher than common terms', () {
      final docs = [
        SemanticSearch.tokenize('the is a unique zebra pattern'),
        SemanticSearch.tokenize('the is a common dog pattern'),
      ];
      final query = SemanticSearch.tokenize('unique zebra');
      final results = SemanticSearch.search(
        queryTokens: query,
        documents: docs,
        topK: 2,
      );

      // Doc 0 has both "unique" and "zebra" → should rank first
      expect(results.first.index, 0);
    });
  });

  group('ScoredEntry', () {
    test('toString shows formatted score', () {
      const entry = ScoredEntry(index: 0, score: 1.23456);
      expect(entry.toString(), contains('1.235'));
    });
  });
}
