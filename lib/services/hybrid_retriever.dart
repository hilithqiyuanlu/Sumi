import 'dart:math';
import 'dart:typed_data';

import '../data/embedding_document_store.dart';

/// A locally ranked retrieval result. [score] is only meaningful within one
/// query and must not be presented as a user-facing confidence value.
class HybridRetrievalResult {
  const HybridRetrievalResult({
    required this.document,
    required this.score,
    required this.semanticScore,
    required this.keywordScore,
  });

  final EmbeddingDocument document;
  final double score;
  final double semanticScore;
  final double keywordScore;
}

/// Ranks locally stored embeddings without sending a query or document to a
/// remote service. It intentionally returns metadata and source information so
/// the chat prompt builder can label the result as data, never as instructions.
class HybridRetriever {
  HybridRetriever(this._documents);

  final EmbeddingDocumentStore _documents;

  Future<List<HybridRetrievalResult>> retrieve({
    required String query,
    required Float32List queryEmbedding,
    Iterable<EmbeddingDocumentSource>? sources,
    String? projectId,
    String? embeddingVersion,
    DateTime? now,
    int limit = 6,
  }) async {
    if (query.trim().isEmpty || limit <= 0) return const [];
    if (queryEmbedding.length != EmbeddingDocument.vectorDimensions) {
      throw ArgumentError.value(
        queryEmbedding.length,
        'queryEmbedding.length',
        'must equal ${EmbeddingDocument.vectorDimensions}',
      );
    }

    final documents = await _documents.query(
      sources: sources,
      projectId: projectId,
      embeddingVersion: embeddingVersion,
    );
    final queryTerms = _keywords(query);
    final referenceTime = now ?? DateTime.now();
    final results = <HybridRetrievalResult>[];
    for (final document in documents) {
      final semantic = _cosineSimilarity(queryEmbedding, document.embedding);
      final keyword = _keywordScore(queryTerms, _keywords(document.text));
      final sourceConfidence =
          _sourceTrust(document.source) * document.confidence.clamp(0.0, 1.0);
      final recency = _recencyScore(document.updatedAt, referenceTime);
      final score =
          (0.65 * semantic) +
          (0.15 * keyword) +
          (0.12 * sourceConfidence) +
          (0.08 * recency);
      results.add(
        HybridRetrievalResult(
          document: document,
          score: score,
          semanticScore: semantic,
          keywordScore: keyword,
        ),
      );
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    final seenSources = <String>{};
    final deduped = <HybridRetrievalResult>[];
    for (final result in results) {
      if (!seenSources.add(result.document.sourceKey)) continue;
      deduped.add(result);
      if (deduped.length == min(limit, 6)) break;
    }
    return deduped;
  }

  static double _cosineSimilarity(Float32List a, Float32List b) {
    var dot = 0.0;
    var aLength = 0.0;
    var bLength = 0.0;
    for (var i = 0; i < a.length; i++) {
      final left = a[i];
      final right = b[i];
      dot += left * right;
      aLength += left * left;
      bLength += right * right;
    }
    if (aLength == 0 || bLength == 0) return 0;
    // Cosine can be negative; local retrieval treats negative similarity as no
    // semantic match instead of allowing it to outweigh trustworthy metadata.
    return max(0, dot / sqrt(aLength * bLength));
  }

  static double _keywordScore(Set<String> queryTerms, Set<String> textTerms) {
    if (queryTerms.isEmpty || textTerms.isEmpty) return 0;
    var matches = 0;
    for (final term in queryTerms) {
      if (textTerms.contains(term)) matches++;
    }
    return matches / queryTerms.length;
  }

  static Set<String> _keywords(String text) {
    final normalized = text.toLowerCase().trim();
    final matches = RegExp(
      r'[a-z0-9]+|[\u4e00-\u9fff]+',
    ).allMatches(normalized);
    final terms = <String>{};
    for (final match in matches) {
      final value = match.group(0)!;
      if (RegExp(r'^[\u4e00-\u9fff]+$').hasMatch(value)) {
        for (var i = 0; i < value.length; i++) {
          terms.add(value.substring(i, i + 1));
          if (i + 1 < value.length) terms.add(value.substring(i, i + 2));
        }
      } else if (value.length > 1) {
        terms.add(value);
      }
    }
    return terms;
  }

  static double _sourceTrust(EmbeddingDocumentSource source) {
    return switch (source) {
      EmbeddingDocumentSource.project || EmbeddingDocumentSource.todo => 1.0,
      EmbeddingDocumentSource.signal ||
      EmbeddingDocumentSource.userMemory ||
      EmbeddingDocumentSource.userMessage => 0.9,
      EmbeddingDocumentSource.assistantMessage => 0.45,
    };
  }

  static double _recencyScore(DateTime updatedAt, DateTime now) {
    final ageHours = max(0, now.difference(updatedAt).inMinutes / 60);
    // A 90-day half-life preserves durable project and memory records while
    // making otherwise equal recent activity easier to find.
    return pow(0.5, ageHours / (24 * 90)).toDouble();
  }
}
