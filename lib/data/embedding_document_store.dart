import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import 'local_database.dart';

/// A stable source category for a locally embedded user record.
enum EmbeddingDocumentSource {
  project,
  todo,
  signal,
  userMemory,
  userMessage,
  assistantMessage,
}

/// A 512-dimensional document vector and the metadata needed to retrieve it.
class EmbeddingDocument {
  static const vectorDimensions = 512;

  const EmbeddingDocument({
    required this.source,
    required this.sourceId,
    required this.updatedAt,
    required this.confidence,
    required this.text,
    required this.embedding,
    required this.embeddingVersion,
    this.projectId,
  });

  final EmbeddingDocumentSource source;
  final String sourceId;
  final String? projectId;
  final DateTime updatedAt;
  final double confidence;
  final String text;
  final Float32List embedding;
  final String embeddingVersion;

  String get sourceKey => '${source.name}:$sourceId';
}

/// SQLite persistence for local semantic-retrieval documents.
///
/// Callers decide which records are indexable. In particular, tool messages and
/// model reasoning must never be supplied to this store.
class EmbeddingDocumentStore {
  EmbeddingDocumentStore(this._store);

  final SumiLocalDatabase _store;
  bool _tableEnsured = false;

  Future<Database> get _db => _store.database;

  Future<void> _ensureTable() async {
    if (_tableEnsured) return;
    final db = await _db;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS embedding_documents (
        source_type TEXT NOT NULL,
        source_id TEXT NOT NULL,
        project_id TEXT,
        updated_at TEXT NOT NULL,
        confidence REAL NOT NULL,
        text_summary TEXT NOT NULL,
        embedding BLOB NOT NULL,
        embedding_version TEXT NOT NULL,
        PRIMARY KEY (source_type, source_id)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_embedding_documents_project
      ON embedding_documents(project_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_embedding_documents_updated
      ON embedding_documents(updated_at)
    ''');
    _tableEnsured = true;
  }

  Future<void> upsert(EmbeddingDocument document) async {
    _validate(document);
    await _ensureTable();
    final db = await _db;
    await db.insert('embedding_documents', {
      'source_type': document.source.name,
      'source_id': document.sourceId,
      'project_id': document.projectId,
      'updated_at': document.updatedAt.toUtc().toIso8601String(),
      'confidence': document.confidence.clamp(0.0, 1.0),
      'text_summary': document.text,
      'embedding': _toBlob(document.embedding),
      'embedding_version': document.embeddingVersion,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> upsertAll(Iterable<EmbeddingDocument> documents) async {
    final values = documents.toList(growable: false);
    for (final document in values) {
      _validate(document);
    }
    if (values.isEmpty) return;
    await _ensureTable();
    final db = await _db;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final document in values) {
        batch.insert('embedding_documents', {
          'source_type': document.source.name,
          'source_id': document.sourceId,
          'project_id': document.projectId,
          'updated_at': document.updatedAt.toUtc().toIso8601String(),
          'confidence': document.confidence.clamp(0.0, 1.0),
          'text_summary': document.text,
          'embedding': _toBlob(document.embedding),
          'embedding_version': document.embeddingVersion,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<EmbeddingDocument?> find(
    EmbeddingDocumentSource source,
    String sourceId,
  ) async {
    await _ensureTable();
    final db = await _db;
    final rows = await db.query(
      'embedding_documents',
      where: 'source_type = ? AND source_id = ?',
      whereArgs: [source.name, sourceId],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<List<EmbeddingDocument>> query({
    Iterable<EmbeddingDocumentSource>? sources,
    String? embeddingVersion,
    String? projectId,
    int? limit,
  }) async {
    await _ensureTable();
    final conditions = <String>[];
    final args = <Object?>[];
    final selectedSources = sources?.toList(growable: false) ?? const [];
    if (selectedSources.isNotEmpty) {
      conditions.add(
        'source_type IN (${List.filled(selectedSources.length, '?').join(',')})',
      );
      args.addAll(selectedSources.map((source) => source.name));
    }
    if (projectId != null) {
      conditions.add('project_id = ?');
      args.add(projectId);
    }
    if (embeddingVersion != null) {
      conditions.add('embedding_version = ?');
      args.add(embeddingVersion);
    }
    final db = await _db;
    final rows = await db.query(
      'embedding_documents',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'updated_at DESC',
      limit: limit,
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<int> count() async {
    await _ensureTable();
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM embedding_documents',
    );
    return (rows.first['count'] as int?) ?? 0;
  }

  Future<Set<String>> embeddingVersions() async {
    await _ensureTable();
    final db = await _db;
    final rows = await db.query(
      'embedding_documents',
      columns: const ['embedding_version'],
      distinct: true,
    );
    return rows
        .map((row) => row['embedding_version'] as String? ?? '')
        .where((version) => version.isNotEmpty)
        .toSet();
  }

  Future<void> delete(EmbeddingDocumentSource source, String sourceId) async {
    await _ensureTable();
    final db = await _db;
    await db.delete(
      'embedding_documents',
      where: 'source_type = ? AND source_id = ?',
      whereArgs: [source.name, sourceId],
    );
  }

  Future<void> deleteByProject(String projectId) async {
    await _ensureTable();
    final db = await _db;
    await db.delete(
      'embedding_documents',
      where: 'project_id = ?',
      whereArgs: [projectId],
    );
  }

  Future<void> clear() async {
    await _ensureTable();
    final db = await _db;
    await db.delete('embedding_documents');
  }

  Future<void> deleteExcept(Set<String> sourceKeys) async {
    await _ensureTable();
    final existing = await query();
    for (final document in existing) {
      if (!sourceKeys.contains(document.sourceKey)) {
        await delete(document.source, document.sourceId);
      }
    }
  }

  static Uint8List _toBlob(Float32List values) {
    final bytes = Uint8List(values.lengthInBytes);
    final view = ByteData.view(bytes.buffer);
    for (var i = 0; i < values.length; i++) {
      view.setFloat32(
        i * Float32List.bytesPerElement,
        values[i],
        Endian.little,
      );
    }
    return bytes;
  }

  static Float32List _fromBlob(Object? raw) {
    if (raw is! Uint8List ||
        raw.lengthInBytes !=
            EmbeddingDocument.vectorDimensions * Float32List.bytesPerElement) {
      throw const FormatException('Invalid local embedding vector');
    }
    final result = Float32List(EmbeddingDocument.vectorDimensions);
    final view = ByteData.view(
      raw.buffer,
      raw.offsetInBytes,
      raw.lengthInBytes,
    );
    for (var i = 0; i < result.length; i++) {
      result[i] = view.getFloat32(
        i * Float32List.bytesPerElement,
        Endian.little,
      );
    }
    return result;
  }

  static EmbeddingDocument _fromRow(Map<String, Object?> row) {
    final sourceName = row['source_type'] as String?;
    final source = EmbeddingDocumentSource.values.firstWhere(
      (value) => value.name == sourceName,
      orElse: () =>
          throw FormatException('Unknown embedding source: $sourceName'),
    );
    return EmbeddingDocument(
      source: source,
      sourceId: row['source_id'] as String,
      projectId: row['project_id'] as String?,
      updatedAt:
          DateTime.tryParse(row['updated_at'] as String? ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      confidence: (row['confidence'] as num?)?.toDouble() ?? 0,
      text: row['text_summary'] as String? ?? '',
      embedding: _fromBlob(row['embedding']),
      embeddingVersion: row['embedding_version'] as String? ?? '',
    );
  }

  static void _validate(EmbeddingDocument document) {
    if (document.sourceId.trim().isEmpty) {
      throw ArgumentError.value(
        document.sourceId,
        'sourceId',
        'must not be empty',
      );
    }
    if (document.text.trim().isEmpty) {
      throw ArgumentError.value(document.text, 'text', 'must not be empty');
    }
    if (document.embedding.length != EmbeddingDocument.vectorDimensions) {
      throw ArgumentError.value(
        document.embedding.length,
        'embedding.length',
        'must equal ${EmbeddingDocument.vectorDimensions}',
      );
    }
    if (!document.confidence.isFinite) {
      throw ArgumentError.value(
        document.confidence,
        'confidence',
        'must be finite',
      );
    }
    if (document.embeddingVersion.trim().isEmpty) {
      throw ArgumentError.value(
        document.embeddingVersion,
        'embeddingVersion',
        'must not be empty',
      );
    }
  }
}
