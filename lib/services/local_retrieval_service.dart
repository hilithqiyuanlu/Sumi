import '../data/embedding_document_store.dart';
import 'hybrid_retriever.dart';
import 'local_embedding_service.dart';

class LocalRetrievalService {
  final EmbeddingCapability embedding;
  final HybridRetriever retriever;

  LocalRetrievalService({required this.embedding, required this.retriever});

  bool shouldRetrieve(String message) {
    final normalized = message.toLowerCase();
    const phrases = [
      '上次', '之前', '过去', '历史', '最近', '进度', '项目', '待办', '事项',
      '计划', '偏好', '习惯', '拖延', '学到哪里', '复盘', '我的', '我曾',
    ];
    return phrases.any(normalized.contains);
  }

  Future<List<HybridRetrievalResult>> retrieve(String query) async {
    if (!embedding.isAvailable || !shouldRetrieve(query)) return const [];
    final vector = (await embedding.embed([query])).single;
    final version = embedding.embeddingVersion;
    if (version == null || version.isEmpty) return const [];
    return retriever.retrieve(
      query: query,
      queryEmbedding: vector,
      embeddingVersion: version,
    );
  }

  static List<Map<String, Object?>> promptData(
    List<HybridRetrievalResult> results,
  ) => [
    for (final result in results)
      {
        'source': result.document.source.name,
        'sourceId': result.document.sourceId,
        'projectId': result.document.projectId,
        'trust': result.document.source == EmbeddingDocumentSource.assistantMessage
            ? 'low_reference'
            : 'user_data',
        'updatedAt': result.document.updatedAt.toIso8601String(),
        'content': result.document.text,
      },
  ];
}
