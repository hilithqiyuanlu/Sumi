import 'dart:typed_data';

import '../data/chat_database.dart';
import '../data/embedding_document_store.dart';
import '../data/signal_database.dart';
import '../models/models.dart';
import 'local_embedding_service.dart';
import 'memory_service.dart';

class EmbeddingIndexProgress {
  final int completed;
  final int total;
  final bool running;
  final String? message;

  const EmbeddingIndexProgress({
    required this.completed,
    required this.total,
    required this.running,
    this.message,
  });
}

/// Builds only local embeddings. It deliberately excludes tool output and
/// reasoning, because neither is stable user knowledge.
class EmbeddingIndexer {
  final EmbeddingDocumentStore documents;
  final EmbeddingCapability embedding;
  final ChatDatabase chatDatabase;
  final SignalDatabase signalDatabase;
  final MemoryService memoryService;
  final List<Project> Function() projects;
  final List<TodoItem> Function() todos;
  final String Function() embeddingVersion;

  bool _cancelled = false;

  EmbeddingIndexer({
    required this.documents,
    required this.embedding,
    required this.chatDatabase,
    required this.signalDatabase,
    required this.memoryService,
    required this.projects,
    required this.todos,
    required this.embeddingVersion,
  });

  void cancel() => _cancelled = true;

  Future<void> rebuildAll({
    void Function(EmbeddingIndexProgress progress)? onProgress,
  }) async {
    if (!embedding.isAvailable) return;
    _cancelled = false;
    final drafts = await _allDrafts();
    final version = embeddingVersion();
    if (version.isEmpty) return;
    final existing = {
      for (final document in await documents.query())
        document.sourceKey: document,
    };
    final sourceKeys = drafts
        .map((draft) => '${draft.source.name}:${draft.sourceId}')
        .toSet();
    await documents.deleteExcept(sourceKeys);
    final pending = drafts
        .where((draft) {
          final stored = existing['${draft.source.name}:${draft.sourceId}'];
          return stored == null ||
              stored.embeddingVersion != version ||
              stored.text != draft.text ||
              stored.projectId != draft.projectId ||
              stored.confidence != draft.confidence;
        })
        .toList(growable: false);
    var completed = 0;
    onProgress?.call(
      EmbeddingIndexProgress(
        completed: completed,
        total: pending.length,
        running: true,
      ),
    );
    for (var start = 0; start < pending.length && !_cancelled; start += 12) {
      final batch = pending.skip(start).take(12).toList(growable: false);
      final vectors = await embedding.embed(
        batch.map((draft) => draft.text).toList(),
      );
      if (_cancelled) break;
      await documents.upsertAll([
        for (var index = 0; index < batch.length; index++)
          batch[index].withEmbedding(vectors[index], version),
      ]);
      completed += batch.length;
      onProgress?.call(
        EmbeddingIndexProgress(
          completed: completed,
          total: pending.length,
          running: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }
    onProgress?.call(
      EmbeddingIndexProgress(
        completed: completed,
        total: pending.length,
        running: false,
        message: _cancelled ? '索引已暂停' : '索引已完成',
      ),
    );
  }

  Future<void> indexProject(Project project) =>
      _indexOne(_projectDraft(project));
  Future<void> indexTodo(TodoItem todo) => _indexOne(_todoDraft(todo));

  Future<void> indexMessages(String conversationId) async {
    for (final message in await chatDatabase.loadMessages(conversationId)) {
      final draft = _messageDraft(message);
      if (draft != null) await _indexOne(draft);
    }
  }

  Future<void> indexMemories() async {
    for (final draft in await _memoryDrafts()) {
      await _indexOne(draft);
    }
  }

  Future<void> indexSignal(UserSignal signal) async {
    await _indexOne(_signalDraft(signal));
  }

  Future<void> _indexOne(_EmbeddingDraft? draft) async {
    if (draft == null || !embedding.isAvailable) return;
    final vector = (await embedding.embed([draft.text])).single;
    final version = embeddingVersion();
    if (version.isNotEmpty) {
      await documents.upsert(draft.withEmbedding(vector, version));
    }
  }

  Future<List<_EmbeddingDraft>> _allDrafts() async {
    final drafts = <_EmbeddingDraft>[
      for (final project in projects()) ..._single(_projectDraft(project)),
      for (final todo in todos()) ..._single(_todoDraft(todo)),
      ...await _memoryDrafts(),
      for (final signal in await signalDatabase.query(
        range: 'all',
        limit: 2000,
      ))
        ..._single(_signalDraft(signal)),
    ];
    // Messages are stored by conversation. Querying all conversations is
    // intentionally delegated to ChatDatabase so the source remains SQLite.
    for (final message in await chatDatabase.loadAllMessages()) {
      final draft = _messageDraft(message);
      if (draft != null) drafts.add(draft);
    }
    return drafts.whereType<_EmbeddingDraft>().toList(growable: false);
  }

  _EmbeddingDraft? _projectDraft(Project project) {
    final text = [
      project.name,
      project.goal,
      project.goalSummary,
      project.level,
    ].where((part) => part.trim().isNotEmpty).join('；');
    return _draft(
      source: EmbeddingDocumentSource.project,
      sourceId: project.id,
      projectId: project.id,
      text: text,
      updatedAt: project.createdAt,
      confidence: 1,
    );
  }

  List<_EmbeddingDraft> _single(_EmbeddingDraft? draft) =>
      draft == null ? const [] : [draft];

  _EmbeddingDraft? _todoDraft(TodoItem todo) => _draft(
    source: EmbeddingDocumentSource.todo,
    sourceId: todo.id,
    projectId: todo.projectId,
    text: [
      todo.title,
      todo.body ?? '',
      todo.date ?? '',
    ].where((part) => part.trim().isNotEmpty).join('；'),
    updatedAt: todo.createdAt,
    confidence: 1,
  );

  _EmbeddingDraft? _signalDraft(UserSignal signal) => _draft(
    source: EmbeddingDocumentSource.signal,
    sourceId:
        'signal-${signal.id ?? '${signal.signal.name}-${signal.time.microsecondsSinceEpoch}'}',
    projectId: signal.projectId,
    text: SignalDatabase.formatForPrompt([signal]),
    updatedAt: signal.time,
    confidence: .9,
  );

  _EmbeddingDraft? _messageDraft(ChatMessage message) {
    if (message.role == 'tool' ||
        message.reasoningContent != null ||
        message.content.trim().isEmpty) {
      return null;
    }
    return _draft(
      source: message.role == 'assistant'
          ? EmbeddingDocumentSource.assistantMessage
          : EmbeddingDocumentSource.userMessage,
      sourceId: message.id,
      text: message.content,
      updatedAt: message.createdAt,
      confidence: message.role == 'assistant' ? .45 : .9,
    );
  }

  Future<List<_EmbeddingDraft>> _memoryDrafts() async {
    final values = <_EmbeddingDraft>[];
    for (final memory in await memoryService.list(includeHistorical: false)) {
      if (memory.type == MemoryType.implicit ||
          memory.type == MemoryType.imported) {
        continue;
      }
      final draft = _draft(
        source: EmbeddingDocumentSource.userMemory,
        sourceId: memory.id,
        projectId: memory.projectId,
        text: '${memory.category}；${memory.content}',
        updatedAt: memory.lastConfirmedAt ?? memory.createdAt,
        confidence: memory.confidence,
      );
      if (draft != null) values.add(draft);
    }
    return values;
  }

  _EmbeddingDraft? _draft({
    required EmbeddingDocumentSource source,
    required String sourceId,
    required String text,
    required DateTime updatedAt,
    required double confidence,
    String? projectId,
  }) {
    final normalized = text.trim();
    if (normalized.isEmpty) return null;
    return _EmbeddingDraft(
      source: source,
      sourceId: sourceId,
      projectId: projectId,
      text: normalized.length > 1200
          ? normalized.substring(0, 1200)
          : normalized,
      updatedAt: updatedAt,
      confidence: confidence,
    );
  }
}

class _EmbeddingDraft {
  final EmbeddingDocumentSource source;
  final String sourceId;
  final String? projectId;
  final String text;
  final DateTime updatedAt;
  final double confidence;

  const _EmbeddingDraft({
    required this.source,
    required this.sourceId,
    required this.projectId,
    required this.text,
    required this.updatedAt,
    required this.confidence,
  });

  EmbeddingDocument withEmbedding(
    Float32List embedding,
    String embeddingVersion,
  ) => EmbeddingDocument(
    source: source,
    sourceId: sourceId,
    projectId: projectId,
    text: text,
    updatedAt: updatedAt,
    confidence: confidence,
    embedding: embedding,
    embeddingVersion: embeddingVersion,
  );
}
