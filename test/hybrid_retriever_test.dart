import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sumi/data/embedding_document_store.dart';
import 'package:sumi/data/local_database.dart';
import 'package:sumi/services/hybrid_retriever.dart';

Float32List _vector(double first, [double second = 0]) {
  final vector = Float32List(EmbeddingDocument.vectorDimensions);
  vector[0] = first;
  vector[1] = second;
  return vector;
}

EmbeddingDocument _document({
  required EmbeddingDocumentSource source,
  required String id,
  required String text,
  required Float32List vector,
  DateTime? updatedAt,
  double confidence = 1,
  String? projectId,
  String embeddingVersion = 'test-v1',
}) {
  return EmbeddingDocument(
    source: source,
    sourceId: id,
    text: text,
    embedding: vector,
    updatedAt: updatedAt ?? DateTime(2026, 1, 1),
    confidence: confidence,
    projectId: projectId,
    embeddingVersion: embeddingVersion,
  );
}

void main() {
  sqfliteFfiInit();

  late Database database;
  late SumiLocalDatabase local;
  late EmbeddingDocumentStore store;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    local = SumiLocalDatabase(database: database);
    store = EmbeddingDocumentStore(local);
  });

  tearDown(() async {
    await local.close();
  });

  test('upsert stores and replaces a 512-dimensional Float32 vector', () async {
    await store.upsert(
      _document(
        source: EmbeddingDocumentSource.todo,
        id: 'todo-1',
        text: '复习英语单词',
        vector: _vector(0.25, 0.5),
        projectId: 'project-1',
      ),
    );
    await store.upsert(
      _document(
        source: EmbeddingDocumentSource.todo,
        id: 'todo-1',
        text: '复习英语语法',
        vector: _vector(0.75, 0.5),
        projectId: 'project-1',
      ),
    );

    expect(await store.count(), 1);
    final value = await store.find(EmbeddingDocumentSource.todo, 'todo-1');
    expect(value?.text, '复习英语语法');
    expect(value?.embedding.length, 512);
    expect(value?.embedding[0], closeTo(0.75, 0.0001));
    expect(
      (await store.query(projectId: 'project-1')).single.sourceId,
      'todo-1',
    );
  });

  test(
    'deletes one source, project documents, and all vectors independently',
    () async {
      await store.upsertAll([
        _document(
          source: EmbeddingDocumentSource.project,
          id: 'project-1',
          text: '日语计划',
          vector: _vector(1),
          projectId: 'project-1',
        ),
        _document(
          source: EmbeddingDocumentSource.todo,
          id: 'todo-1',
          text: '背单词',
          vector: _vector(1),
          projectId: 'project-1',
        ),
        _document(
          source: EmbeddingDocumentSource.userMemory,
          id: 'memory-1',
          text: '晚上效率高',
          vector: _vector(1),
        ),
      ]);

      await store.delete(EmbeddingDocumentSource.project, 'project-1');
      expect(await store.count(), 2);
      await store.deleteByProject('project-1');
      expect(await store.count(), 1);
      await store.clear();
      expect(await store.count(), 0);
    },
  );

  test(
    'rejects empty documents and vectors with a non-model dimension',
    () async {
      expect(
        () => store.upsert(
          _document(
            source: EmbeddingDocumentSource.todo,
            id: 'todo-1',
            text: '',
            vector: _vector(1),
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => store.upsert(
          EmbeddingDocument(
            source: EmbeddingDocumentSource.todo,
            sourceId: 'todo-1',
            text: '有效文本',
            embedding: Float32List(3),
            updatedAt: DateTime(2026),
            confidence: 1,
            embeddingVersion: 'test-v1',
          ),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'hybrid retrieval prefers trustworthy user data over assistant history',
    () async {
      final now = DateTime(2026, 7, 15, 10);
      await store.upsertAll([
        _document(
          source: EmbeddingDocumentSource.assistantMessage,
          id: 'assistant-1',
          text: '你上次日语学习到假名',
          vector: _vector(1),
          updatedAt: now,
        ),
        _document(
          source: EmbeddingDocumentSource.todo,
          id: 'todo-1',
          text: '日语学习：复习五十音图',
          vector: _vector(1),
          updatedAt: now,
        ),
        _document(
          source: EmbeddingDocumentSource.todo,
          id: 'todo-2',
          text: '无关事项',
          vector: _vector(0, 1),
          updatedAt: now,
        ),
      ]);

      final results = await HybridRetriever(
        store,
      ).retrieve(query: '我上次日语学习到哪里', queryEmbedding: _vector(1), now: now);

      expect(results, hasLength(3));
      expect(results.first.document.source, EmbeddingDocumentSource.todo);
      expect(results.first.document.sourceId, 'todo-1');
      expect(results.first.keywordScore, greaterThan(0));
    },
  );

  test('retrieval obeys six-result cap and source/project filters', () async {
    final documents = List.generate(
      8,
      (index) => _document(
        source: EmbeddingDocumentSource.signal,
        id: 'signal-$index',
        text: '学习进度 $index',
        vector: _vector(1),
        projectId: index.isEven ? 'project-a' : 'project-b',
      ),
    );
    await store.upsertAll(documents);

    final results = await HybridRetriever(store).retrieve(
      query: '学习进度',
      queryEmbedding: _vector(1),
      sources: [EmbeddingDocumentSource.signal],
      projectId: 'project-a',
      limit: 99,
    );

    expect(results, hasLength(4));
    expect(
      results.every((result) => result.document.projectId == 'project-a'),
      isTrue,
    );
  });

  test(
    'retrieval never mixes vectors created by different model versions',
    () async {
      await store.upsertAll([
        _document(
          source: EmbeddingDocumentSource.todo,
          id: 'current',
          text: '当前索引',
          vector: _vector(1),
        ),
        EmbeddingDocument(
          source: EmbeddingDocumentSource.todo,
          sourceId: 'old',
          text: '旧索引',
          embedding: _vector(1),
          embeddingVersion: 'test-v0',
          updatedAt: DateTime(2026),
          confidence: 1,
        ),
      ]);

      final results = await HybridRetriever(store).retrieve(
        query: '索引',
        queryEmbedding: _vector(1),
        embeddingVersion: 'test-v1',
      );

      expect(results.map((result) => result.document.sourceId), ['current']);
    },
  );
}
