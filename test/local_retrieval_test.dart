import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sumi/data/embedding_document_store.dart';
import 'package:sumi/data/local_database.dart';
import 'package:sumi/services/hybrid_retriever.dart';
import 'package:sumi/services/local_embedding_service.dart';
import 'package:sumi/services/local_retrieval_service.dart';

class _Embedding implements EmbeddingCapability {
  bool available;
  int calls = 0;

  _Embedding(this.available);

  @override
  bool get isAvailable => available;

  @override
  String? get unavailableReason => available ? null : '本地模型未下载';

  @override
  String? get embeddingVersion => available ? 'test-v1' : null;

  @override
  Future<List<Float32List>> embed(List<String> texts) async {
    calls++;
    final vector = Float32List(EmbeddingDocument.vectorDimensions)..[0] = 1;
    return [for (final _ in texts) vector];
  }
}

EmbeddingDocument _document({
  required EmbeddingDocumentSource source,
  required String id,
  required String text,
}) {
  final vector = Float32List(EmbeddingDocument.vectorDimensions)..[0] = 1;
  return EmbeddingDocument(
    source: source,
    sourceId: id,
    text: text,
    updatedAt: DateTime(2026, 7, 15),
    confidence: source == EmbeddingDocumentSource.assistantMessage ? .45 : .9,
    embedding: vector,
    embeddingVersion: 'test-v1',
  );
}

void main() {
  sqfliteFfiInit();

  test('普通知识问题不触发本地检索', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    final embedding = _Embedding(true);
    final service = LocalRetrievalService(
      embedding: embedding,
      retriever: HybridRetriever(
        EmbeddingDocumentStore(SumiLocalDatabase(database: db)),
      ),
    );

    expect(service.shouldRetrieve('量子力学是什么'), isFalse);
    expect(service.shouldRetrieve('今晚怎么安排学习'), isTrue);
    expect(await service.retrieve('量子力学是什么'), isEmpty);
    expect(embedding.calls, 0);
  });

  test('本地模型未下载时绝不调用向量化', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    final embedding = _Embedding(false);
    final service = LocalRetrievalService(
      embedding: embedding,
      retriever: HybridRetriever(
        EmbeddingDocumentStore(SumiLocalDatabase(database: db)),
      ),
    );

    expect(await service.retrieve('我上次学到哪里了'), isEmpty);
    expect(embedding.calls, 0);
  });

  test('检索上下文标记低可信助手历史，不当作用户事实', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    final store = EmbeddingDocumentStore(SumiLocalDatabase(database: db));
    await store.upsertAll([
      _document(
        source: EmbeddingDocumentSource.todo,
        id: 'todo-1',
        text: '复习日语假名',
      ),
      _document(
        source: EmbeddingDocumentSource.assistantMessage,
        id: 'assistant-1',
        text: '你已掌握日语假名',
      ),
    ]);
    final service = LocalRetrievalService(
      embedding: _Embedding(true),
      retriever: HybridRetriever(store),
    );

    final results = await service.retrieve('我上次日语学到哪里了');
    final data = LocalRetrievalService.promptData(results);
    expect(
      data.any((row) => row['source'] == 'todo' && row['trust'] == 'user_data'),
      isTrue,
    );
    expect(
      data.any(
        (row) =>
            row['source'] == 'assistantMessage' &&
            row['trust'] == 'low_reference',
      ),
      isTrue,
    );
  });
}
