import 'dart:convert';
import 'dart:io' as io;

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../data/local_database.dart';
import '../utils/utils.dart';
import 'memory_extraction.dart';

enum MemoryType { explicit, current, implicit, milestone, imported }

enum MemoryStatus { active, inactive, disabled, superseded }

enum MemorySource { userMessage, manual, recommendation, project, legacy }

class MemoryItem {
  final String id;
  final MemoryType type;
  final String category;
  final String content;
  final String? projectId;
  final MemoryStatus status;
  final double confidence;
  final MemorySource source;
  final String? replacesId;
  final DateTime createdAt;
  final DateTime? lastConfirmedAt;

  const MemoryItem({
    required this.id,
    required this.type,
    required this.category,
    required this.content,
    this.projectId,
    required this.status,
    required this.confidence,
    required this.source,
    this.replacesId,
    required this.createdAt,
    this.lastConfirmedAt,
  });

  bool get isUsable => status == MemoryStatus.active;
}

class MemoryEvidence {
  final String id;
  final String memoryId;
  final String kind;
  final String? referenceId;
  final String summary;
  final DateTime occurredAt;

  const MemoryEvidence({
    required this.id,
    required this.memoryId,
    required this.kind,
    this.referenceId,
    required this.summary,
    required this.occurredAt,
  });
}

/// Content-free aggregate used by the developer diagnostics screen.
class MemoryExtractionDiagnostics {
  final int applied;
  final int ignored;
  final int failed;
  final Map<String, int> failuresByCategory;
  final int retryable;
  final int retries;
  final Map<String, int> sources;

  const MemoryExtractionDiagnostics({
    required this.applied,
    required this.ignored,
    required this.failed,
    required this.failuresByCategory,
    this.retryable = 0,
    this.retries = 0,
    this.sources = const {},
  });
}

class MemorySuggestion {
  final String eventId;
  final String text;
  final String topic;
  final String? memoryId;
  final String source;

  const MemorySuggestion({
    required this.eventId,
    required this.text,
    required this.topic,
    this.memoryId,
    required this.source,
  });
}

/// The single writer for durable user knowledge. Facts and their evidence are
/// stored separately so a conclusion can be disabled without deleting history.
class MemoryService {
  MemoryService(this._store, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final SumiLocalDatabase _store;
  final DateTime Function() _now;
  static const _activeConfidence = .85;
  static const _topicTemplates = <String, String>{
    'plan': '帮我制定今天的学习计划',
    'priority': '建议我今天优先完成什么',
    'review': '帮我回顾一下最近学了什么',
    'progress': '帮我分析一下学习进度',
    'adjust': '帮我调整今天的学习计划',
    'method': '推荐一个学习方法',
    'resource': '推荐相关学习资源',
  };

  Future<Database> get _db => _store.database;

  Future<void> ensureTables() async {
    final db = await _db;
    await db.execute('''CREATE TABLE IF NOT EXISTS memory_items (
      id TEXT PRIMARY KEY, type TEXT NOT NULL, category TEXT NOT NULL,
      content TEXT NOT NULL, project_id TEXT, status TEXT NOT NULL,
      confidence REAL NOT NULL, source TEXT NOT NULL, replaces_id TEXT,
      created_at TEXT NOT NULL, last_confirmed_at TEXT)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS memory_evidence (
      id TEXT PRIMARY KEY, memory_id TEXT NOT NULL, kind TEXT NOT NULL,
      reference_id TEXT, summary TEXT NOT NULL, occurred_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      FOREIGN KEY(memory_id) REFERENCES memory_items(id) ON DELETE CASCADE)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS memory_migration_state (
      key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_items_status ON memory_items(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_items_type ON memory_items(type)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_items_project ON memory_items(project_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_evidence_memory ON memory_evidence(memory_id)',
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS memory_extraction_runs (
      message_id TEXT PRIMARY KEY, status TEXT NOT NULL,
      decision_json TEXT, error_category TEXT, processed_at TEXT NOT NULL)''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_extraction_runs_processed ON memory_extraction_runs(processed_at)',
    );
    await _ensureRecommendationColumn(db);
    await _ensureExtractionFailureColumn(db);
    await _ensureExtractionRunColumns(db);
    await db.execute('DROP TABLE IF EXISTS memory_tags');
    await db.update(
      'memory_items',
      {'project_id': null},
      where: 'type IN (?, ?)',
      whereArgs: [MemoryType.explicit.name, MemoryType.current.name],
    );
  }

  Future<void> _ensureRecommendationColumn(Database db) async {
    final columns = await db.rawQuery(
      'PRAGMA table_info(recommendation_events)',
    );
    if (columns.isEmpty) {
      await db.execute(
        '''CREATE TABLE recommendation_events (
        id TEXT PRIMARY KEY, text TEXT NOT NULL, topic TEXT NOT NULL,
        memory_id TEXT, shown_at TEXT NOT NULL, selected_at TEXT,
        feedback_at TEXT, feedback_type TEXT, context_json TEXT NOT NULL DEFAULT '{}')''',
      );
      return;
    }
    if (!columns.any((row) => row['name'] == 'memory_id')) {
      await db.execute(
        'ALTER TABLE recommendation_events ADD COLUMN memory_id TEXT',
      );
    }
  }

  Future<void> _ensureExtractionFailureColumn(Database db) async {
    final columns = await db.rawQuery(
      'PRAGMA table_info(memory_extraction_runs)',
    );
    if (!columns.any((row) => row['name'] == 'error_category')) {
      await db.execute(
        'ALTER TABLE memory_extraction_runs ADD COLUMN error_category TEXT',
      );
    }
  }

  Future<void> _ensureExtractionRunColumns(Database db) async {
    final columns = await db.rawQuery(
      'PRAGMA table_info(memory_extraction_runs)',
    );
    if (!columns.any((row) => row['name'] == 'attempt_count')) {
      await db.execute(
        'ALTER TABLE memory_extraction_runs ADD COLUMN attempt_count INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!columns.any((row) => row['name'] == 'source')) {
      await db.execute(
        "ALTER TABLE memory_extraction_runs ADD COLUMN source TEXT NOT NULL DEFAULT 'chat'",
      );
    }
  }

  Future<List<MemoryItem>> list({bool includeHistorical = true}) async {
    await ensureTables();
    final rows = await (await _db).query(
      'memory_items',
      where: includeHistorical ? null : 'status = ?',
      whereArgs: includeHistorical ? null : [MemoryStatus.active.name],
      orderBy: 'created_at DESC',
    );
    return rows.map(_itemFromRow).toList(growable: false);
  }

  Future<List<MemoryEvidence>> evidenceFor(String memoryId) async {
    await ensureTables();
    final rows = await (await _db).query(
      'memory_evidence',
      where: 'memory_id = ?',
      whereArgs: [memoryId],
      orderBy: 'occurred_at DESC',
    );
    return rows.map(_evidenceFromRow).toList(growable: false);
  }

  Future<Set<String>> sourceMessageIdsFor(Iterable<String> messageIds) async {
    final ids = messageIds.toSet().toList(growable: false);
    if (ids.isEmpty) return <String>{};
    await ensureTables();
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await (await _db).query(
      'memory_evidence',
      columns: const ['reference_id'],
      where: 'kind = ? AND reference_id IN ($placeholders)',
      whereArgs: ['user_message', ...ids],
    );
    return rows
        .map((row) => row['reference_id'] as String?)
        .whereType<String>()
        .toSet();
  }

  Future<Set<String>> sourceMessageIdsForMemory(String memoryId) async {
    await ensureTables();
    final rows = await (await _db).query(
      'memory_evidence',
      columns: const ['reference_id'],
      where: 'memory_id = ? AND kind = ?',
      whereArgs: [memoryId, 'user_message'],
    );
    return rows
        .map((row) => row['reference_id'] as String?)
        .whereType<String>()
        .toSet();
  }

  static const _currentExpiry = Duration(days: 30);

  Future<List<MemoryExtractionCandidate>> extractionCandidates({
    int limit = 6,
  }) async {
    await ensureTables();
    await expireStaleCurrent();
    final rows = await (await _db).query(
      'memory_items',
      where: 'status = ? AND (type = ? OR type = ?)',
      whereArgs: [
        MemoryStatus.active.name,
        MemoryType.explicit.name,
        MemoryType.current.name,
      ],
      orderBy: 'last_confirmed_at DESC, created_at DESC',
      limit: limit,
    );
    return rows
        .map((row) {
          final item = _itemFromRow(row);
          return MemoryExtractionCandidate(
            id: item.id,
            type: item.type,
            category: item.category,
            content: item.content,
          );
        })
        .toList(growable: false);
  }

  /// 是否已有一条用户原话作为记忆证据。日结补漏据此跳过白天已成功
  /// 采集的内容，避免同一句话被重复沉淀。
  Future<bool> hasUserMessageEvidence(String messageId) async {
    await ensureTables();
    final rows = await (await _db).query(
      'memory_evidence',
      columns: const ['id'],
      where: 'kind = ? AND reference_id = ?',
      whereArgs: ['user_message', messageId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Claims a persisted message for exactly one background extraction run.
  Future<bool> claimExtraction(
    String messageId, {
    String source = 'chat',
  }) async {
    await ensureTables();
    try {
      await (await _db).insert('memory_extraction_runs', {
        'message_id': messageId,
        'status': 'pending',
        'attempt_count': 0,
        'source': source,
        'processed_at': _now().toIso8601String(),
      });
      return true;
    } on DatabaseException {
      return false;
    }
  }

  Future<List<String>> retryableExtractionIds() async {
    await ensureTables();
    final rows = await (await _db).query(
      'memory_extraction_runs',
      columns: const ['message_id'],
      where:
          "status = ? AND error_category IN ('runtime', 'no_valid_decision') AND attempt_count < 2",
      whereArgs: const ['failed'],
      orderBy: 'processed_at ASC',
      limit: 20,
    );
    return rows
        .map((row) => row['message_id'] as String)
        .toList(growable: false);
  }

  Future<bool> reclaimExtraction(String messageId) async {
    await ensureTables();
    final changed = await (await _db).rawUpdate(
      '''UPDATE memory_extraction_runs
         SET status = ?, error_category = NULL,
             attempt_count = attempt_count + 1, processed_at = ?
         WHERE message_id = ? AND status = ?
           AND error_category IN ('runtime', 'no_valid_decision')
           AND attempt_count < 2''',
      ['pending', _now().toIso8601String(), messageId, 'failed'],
    );
    return changed == 1;
  }

  Future<void> finishExtraction(
    String messageId, {
    required String status,
    MemoryExtractionDecision? decision,
    String? errorCategory,
  }) async {
    await ensureTables();
    await (await _db).update(
      'memory_extraction_runs',
      {
        'status': status,
        'decision_json': decision == null
            ? null
            : jsonEncode(decision.toJson()),
        'error_category': errorCategory,
        'processed_at': _now().toIso8601String(),
      },
      where: 'message_id = ? AND status != ?',
      whereArgs: [messageId, 'cancelled'],
    );
  }

  /// Cancels queued extraction and removes message evidence. Explicit/current
  /// memories without any remaining user quote are deleted as well.
  Future<Set<String>> removeMessageSources(Iterable<String> messageIds) async {
    final ids = messageIds.toSet().toList(growable: false);
    if (ids.isEmpty) return <String>{};
    await ensureTables();
    final db = await _db;
    final placeholders = List.filled(ids.length, '?').join(',');
    final deletedMemoryIds = <String>{};
    await db.transaction((txn) async {
      final now = _now().toIso8601String();
      for (final messageId in ids) {
        await txn.insert('memory_extraction_runs', {
          'message_id': messageId,
          'status': 'cancelled',
          'attempt_count': 0,
          'source': 'deleted_message',
          'processed_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await txn.rawUpdate(
        'UPDATE memory_extraction_runs SET status = ?, error_category = NULL, '
        'processed_at = ? WHERE message_id IN ($placeholders)',
        ['cancelled', now, ...ids],
      );

      final affected = await txn.query(
        'memory_evidence',
        columns: const ['memory_id'],
        where: 'kind = ? AND reference_id IN ($placeholders)',
        whereArgs: ['user_message', ...ids],
      );
      final affectedMemoryIds = affected
          .map((row) => row['memory_id'] as String)
          .toSet();
      await txn.delete(
        'memory_evidence',
        where: 'kind = ? AND reference_id IN ($placeholders)',
        whereArgs: ['user_message', ...ids],
      );

      for (final memoryId in affectedMemoryIds) {
        final rows = await txn.rawQuery(
          '''SELECT m.type,
                    EXISTS(
                      SELECT 1 FROM memory_evidence e
                      WHERE e.memory_id = m.id AND e.kind = 'user_message'
                    ) AS has_user_evidence
             FROM memory_items m WHERE m.id = ? LIMIT 1''',
          [memoryId],
        );
        if (rows.isEmpty) continue;
        final type = rows.single['type'] as String?;
        final hasEvidence = (rows.single['has_user_evidence'] as num?) == 1;
        if (hasEvidence ||
            (type != MemoryType.explicit.name &&
                type != MemoryType.current.name)) {
          continue;
        }
        await txn.delete(
          'memory_evidence',
          where: 'memory_id = ?',
          whereArgs: [memoryId],
        );
        await txn.delete(
          'memory_items',
          where: 'id = ?',
          whereArgs: [memoryId],
        );
        deletedMemoryIds.add(memoryId);
      }
    });
    return deletedMemoryIds;
  }

  Future<MemoryExtractionDiagnostics> extractionDiagnostics({
    int days = 7,
  }) async {
    await ensureTables();
    final start = _now().subtract(Duration(days: days - 1)).toIso8601String();
    final rows = await (await _db).rawQuery(
      '''SELECT status, error_category, source, COUNT(*) AS total,
                COALESCE(SUM(attempt_count), 0) AS retries
         FROM memory_extraction_runs
         WHERE processed_at >= ?
         GROUP BY status, error_category, source''',
      [start],
    );
    var applied = 0;
    var ignored = 0;
    var failed = 0;
    final failures = <String, int>{};
    final sources = <String, int>{};
    var retries = 0;
    for (final row in rows) {
      final status = row['status'] as String? ?? '';
      final total = (row['total'] as num?)?.toInt() ?? 0;
      retries += (row['retries'] as num?)?.toInt() ?? 0;
      final source = row['source'] as String? ?? 'chat';
      sources[source] = (sources[source] ?? 0) + total;
      switch (status) {
        case 'applied':
          applied += total;
        case 'ignored':
          ignored += total;
        case 'failed':
          failed += total;
          final category = row['error_category'] as String? ?? 'unknown';
          failures[category] = (failures[category] ?? 0) + total;
      }
    }
    return MemoryExtractionDiagnostics(
      applied: applied,
      ignored: ignored,
      failed: failed,
      failuresByCategory: Map.unmodifiable(failures),
      retries: retries,
      sources: Map.unmodifiable(sources),
    );
  }

  /// Applies a model decision only after validating every field against the
  /// persisted message boundary. Invalid decisions are kept as failed runs.
  Future<bool> applyExtractionDecision({
    required String messageId,
    required String userMessage,
    required MemoryExtractionDecision decision,
    required Set<String> candidateReplaceIds,
  }) async {
    await ensureTables();
    if (decision.action == MemoryExtractionAction.ignore) {
      await finishExtraction(messageId, status: 'ignored', decision: decision);
      return true;
    }
    final category = decision.category?.trim() ?? '';
    final content = decision.content?.trim() ?? '';
    final quote = decision.quotedText?.trim() ?? '';
    final isCurrent = decision.type == MemoryType.current;
    final valid = isCurrent
        ? const {'progress', 'difficulty', 'short_term_constraint'}
        : const {'preference', 'goal', 'constraint'};
    if (decision.confidence < .85) {
      await finishExtraction(messageId, status: 'ignored', decision: decision);
      return false;
    }
    if (!valid.contains(category) ||
        content.length < 2 ||
        content.length > 200 ||
        quote.isEmpty ||
        quote.length > 500 ||
        !userMessage.contains(quote)) {
      await finishExtraction(
        messageId,
        status: 'failed',
        decision: decision,
        errorCategory: 'validation',
      );
      return false;
    }
    final replaceId = decision.replacesId?.trim();
    if ((decision.action == MemoryExtractionAction.replace &&
            (replaceId == null || !candidateReplaceIds.contains(replaceId))) ||
        (decision.action == MemoryExtractionAction.save && replaceId != null)) {
      await finishExtraction(
        messageId,
        status: 'failed',
        decision: decision,
        errorCategory: 'replacement',
      );
      return false;
    }
    final db = await _db;
    final now = _now();
    try {
      await db.transaction((txn) async {
        if (isCurrent) {
          await txn.update(
            'memory_items',
            {'status': MemoryStatus.superseded.name},
            where: 'type = ? AND category = ? AND status = ?',
            whereArgs: [
              MemoryType.current.name,
              category,
              MemoryStatus.active.name,
            ],
          );
        } else if (decision.action == MemoryExtractionAction.replace) {
          final oldRows = await txn.query(
            'memory_items',
            where: 'id = ? AND type = ? AND status = ?',
            whereArgs: [
              replaceId,
              MemoryType.explicit.name,
              MemoryStatus.active.name,
            ],
            limit: 1,
          );
          if (oldRows.isEmpty) {
            throw const FormatException(
              'replace target is not active explicit memory',
            );
          }
          await txn.update(
            'memory_items',
            {'status': MemoryStatus.superseded.name},
            where: 'id = ?',
            whereArgs: [replaceId],
          );
        }
        final duplicates = await txn.query(
          'memory_items',
          where: 'type = ? AND status = ? AND category = ? AND content = ?',
          whereArgs: [
            decision.type.name,
            MemoryStatus.active.name,
            category,
            content,
          ],
          limit: 1,
        );
        final memoryId = duplicates.isEmpty
            ? newSumiId('memory')
            : duplicates.single['id'] as String;
        final run = await txn.query(
          'memory_extraction_runs',
          where: 'message_id = ? AND status = ?',
          whereArgs: [messageId, 'pending'],
          limit: 1,
        );
        if (run.isEmpty) {
          throw const FormatException('extraction run is not pending');
        }
        if (duplicates.isEmpty) {
          await txn.insert('memory_items', {
            'id': memoryId,
            'type': decision.type.name,
            'category': category,
            'content': content,
            'project_id': null,
            'status': MemoryStatus.active.name,
            'confidence': 1.0,
            'source': MemorySource.userMessage.name,
            'replaces_id': decision.action == MemoryExtractionAction.replace
                ? replaceId
                : null,
            'created_at': now.toIso8601String(),
            'last_confirmed_at': now.toIso8601String(),
          });
        } else {
          await txn.update(
            'memory_items',
            {'last_confirmed_at': now.toIso8601String()},
            where: 'id = ?',
            whereArgs: [memoryId],
          );
        }
        await txn.insert(
          'memory_evidence',
          _evidenceToRow(
            MemoryEvidence(
              id: newSumiId('evidence'),
              memoryId: memoryId,
              kind: 'user_message',
              referenceId: messageId,
              summary: quote,
              occurredAt: now,
            ),
          ),
        );
        await txn.update(
          'memory_extraction_runs',
          {
            'status': 'applied',
            'decision_json': jsonEncode(decision.toJson()),
            'processed_at': now.toIso8601String(),
          },
          where: 'message_id = ?',
          whereArgs: [messageId],
        );
      });
      return true;
    } catch (_) {
      await finishExtraction(
        messageId,
        status: 'failed',
        decision: decision,
        errorCategory: 'storage',
      );
      return false;
    }
  }

  /// 日结补漏只能新增一条有原话证据的明确记忆。它不依赖逐消息提取的
  /// pending run，也绝不替换已有记忆，避免日结改变已经确认过的事实。
  Future<bool> applyDailyBackfillDecision({
    required String messageId,
    required String userMessage,
    required MemoryExtractionDecision decision,
  }) async {
    await ensureTables();
    if (decision.action != MemoryExtractionAction.save ||
        decision.type != MemoryType.explicit) {
      return false;
    }
    final category = decision.category?.trim() ?? '';
    final content = decision.content?.trim() ?? '';
    final quote = decision.quotedText?.trim() ?? '';
    if (!const {'preference', 'goal', 'constraint'}.contains(category) ||
        content.length < 2 ||
        content.length > 200 ||
        quote.isEmpty ||
        quote.length > 500 ||
        !userMessage.contains(quote)) {
      return false;
    }
    final db = await _db;
    final duplicate = await db.query(
      'memory_items',
      where: 'type = ? AND status = ? AND category = ? AND content = ?',
      whereArgs: [
        MemoryType.explicit.name,
        MemoryStatus.active.name,
        category,
        content,
      ],
      limit: 1,
    );
    if (duplicate.isNotEmpty) return false;
    try {
      await _add(
        type: MemoryType.explicit,
        category: category,
        content: content,
        confidence: 1,
        source: MemorySource.userMessage,
        evidenceKind: 'user_message',
        evidenceReferenceId: messageId,
        evidenceSummary: quote,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<MemoryItem> addExplicit({
    MemoryType type = MemoryType.explicit,
    required String category,
    required String content,
    required String quotedText,
    required String messageId,
    String? replacesId,
  }) => _add(
    type: type,
    category: category,
    content: content,
    confidence: 1,
    source: MemorySource.userMessage,
    replacesId: replacesId,
    evidenceKind: 'user_message',
    evidenceReferenceId: messageId,
    evidenceSummary: quotedText,
  );

  Future<MemoryItem> addMilestone({
    required String projectId,
    required String content,
    required String messageId,
    required String quote,
    required String todoId,
    required String todoTitle,
  }) async {
    final item = await _add(
      type: MemoryType.milestone,
      category: 'milestone',
      content: content,
      projectId: projectId,
      confidence: 1,
      source: MemorySource.project,
      evidenceKind: 'user_message',
      evidenceReferenceId: messageId,
      evidenceSummary: quote,
    );
    await (await _db).insert(
      'memory_evidence',
      _evidenceToRow(
        MemoryEvidence(
          id: newSumiId('evidence'),
          memoryId: item.id,
          kind: 'completed_todo',
          referenceId: todoId,
          summary: todoTitle,
          occurredAt: _now(),
        ),
      ),
    );
    return item;
  }

  Future<MemoryItem> _add({
    required MemoryType type,
    required String category,
    required String content,
    String? projectId,
    required double confidence,
    required MemorySource source,
    String? replacesId,
    required String evidenceKind,
    String? evidenceReferenceId,
    required String evidenceSummary,
  }) async {
    await ensureTables();
    final now = _now();
    final id = newSumiId('memory');
    final item = MemoryItem(
      id: id,
      type: type,
      category: category.trim(),
      content: content.trim(),
      projectId: projectId,
      status: MemoryStatus.active,
      confidence: confidence,
      source: source,
      replacesId: replacesId,
      createdAt: now,
      lastConfirmedAt: now,
    );
    final db = await _db;
    await db.transaction((txn) async {
      if (evidenceKind == 'user_message' &&
          evidenceReferenceId != null &&
          evidenceReferenceId.isNotEmpty) {
        final cancelled = await txn.query(
          'memory_extraction_runs',
          columns: const ['message_id'],
          where: 'message_id = ? AND status = ?',
          whereArgs: [evidenceReferenceId, 'cancelled'],
          limit: 1,
        );
        if (cancelled.isNotEmpty) {
          throw const FormatException('source message was deleted');
        }
      }
      if (replacesId != null) {
        await txn.update(
          'memory_items',
          {'status': MemoryStatus.superseded.name},
          where: 'id = ?',
          whereArgs: [replacesId],
        );
      }
      await txn.insert('memory_items', _itemToRow(item));
      await txn.insert(
        'memory_evidence',
        _evidenceToRow(
          MemoryEvidence(
            id: newSumiId('evidence'),
            memoryId: id,
            kind: evidenceKind,
            referenceId: evidenceReferenceId,
            summary: evidenceSummary,
            occurredAt: now,
          ),
        ),
      );
    });
    return MemoryItem(
      id: item.id,
      type: item.type,
      category: item.category,
      content: item.content,
      projectId: item.projectId,
      status: item.status,
      confidence: item.confidence,
      source: item.source,
      replacesId: item.replacesId,
      createdAt: item.createdAt,
      lastConfirmedAt: item.lastConfirmedAt,
    );
  }

  Future<void> update(
    String id, {
    MemoryType? type,
    required String category,
    required String content,
  }) async {
    await ensureTables();
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'memory_items',
        columns: const ['type', 'category'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final previousType = MemoryType.values.firstWhere(
        (value) => value.name == rows.single['type'],
        orElse: () => MemoryType.imported,
      );
      final nextType = type ?? previousType;
      if (nextType != MemoryType.explicit && nextType != MemoryType.current) {
        throw const FormatException('只能编辑长期记忆或当前关注');
      }
      final normalizedCategory = _categoryForType(nextType, category);
      if (nextType == MemoryType.current) {
        await txn.update(
          'memory_items',
          {'status': MemoryStatus.superseded.name},
          where: 'id != ? AND type = ? AND category = ? AND status = ?',
          whereArgs: [
            id,
            MemoryType.current.name,
            normalizedCategory,
            MemoryStatus.active.name,
          ],
        );
      }
      await txn.update(
        'memory_items',
        {
          'type': nextType.name,
          'category': normalizedCategory,
          'content': content.trim(),
          'project_id': null,
          'last_confirmed_at': _now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  static String _categoryForType(MemoryType type, String category) {
    final normalized = category.trim();
    if (type == MemoryType.current) {
      return const {
            'progress',
            'difficulty',
            'short_term_constraint',
          }.contains(normalized)
          ? normalized
          : 'progress';
    }
    return const {'preference', 'goal', 'constraint'}.contains(normalized)
        ? normalized
        : 'preference';
  }

  Future<void> setStatus(String id, MemoryStatus status) async {
    await ensureTables();
    await (await _db).update(
      'memory_items',
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    await ensureTables();
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        'memory_evidence',
        where: 'memory_id = ?',
        whereArgs: [id],
      );
      await txn.delete('memory_items', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> expireStaleCurrent() async {
    await ensureTables();
    final cutoff = _now().subtract(_currentExpiry).toIso8601String();
    await (await _db).update(
      'memory_items',
      {'status': MemoryStatus.inactive.name},
      where:
          'type = ? AND status = ? AND last_confirmed_at IS NOT NULL AND last_confirmed_at < ?',
      whereArgs: [MemoryType.current.name, MemoryStatus.active.name, cutoff],
    );
  }

  Future<List<MemoryItem>> search(
    String query, {
    int limit = 8,
    Map<String, double> semanticScores = const {},
  }) async {
    await expireStaleCurrent();
    final normalized = query.trim().toLowerCase();
    final candidates = await list(includeHistorical: false);
    final scored = candidates
        .where((item) {
          return item.type != MemoryType.imported &&
              item.type != MemoryType.implicit;
        })
        .map((item) {
          final topicText = item.category == 'suggestion_topic'
              ? (_topicTemplates[item.content] ?? '')
              : '';
          final haystack = '${item.category} ${item.content} $topicText'
              .toLowerCase();
          final keywordScore = _matchScore(normalized, haystack);
          final semanticScore = semanticScores[item.id] ?? 0;
          final typePriority = switch (item.type) {
            MemoryType.current => 3.5,
            MemoryType.explicit => 3.0,
            MemoryType.implicit => .5,
            MemoryType.milestone => 1.5,
            MemoryType.imported => 0.0,
          };
          final categoryPriority = item.category == 'constraint' ? 1.5 : 0.0;
          final isRelevant =
              normalized.isEmpty || keywordScore > 0 || semanticScore >= .35;
          return (
            item: item,
            isRelevant: isRelevant,
            score:
                (keywordScore * 1.2) +
                (semanticScore * 5) +
                typePriority +
                categoryPriority,
          );
        })
        .where((value) => value.isRelevant)
        .toList();
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored
        .take(limit)
        .map((value) => value.item)
        .toList(growable: false);
  }

  Future<List<MemoryItem>> hotForAgent(
    String query, {
    Map<String, double> semanticScores = const {},
  }) => search(query, limit: 4, semanticScores: semanticScores);

  Future<String> formatForAgent(
    String query, {
    int limit = 8,
    Map<String, double> semanticScores = const {},
  }) async {
    final items = await search(
      query,
      limit: limit,
      semanticScores: semanticScores,
    );
    if (items.isEmpty) return '（没有相关记忆）';
    return jsonEncode([
      for (final item in items)
        {
          'id': item.id,
          'type': item.type.name,
          'category': item.category,
          'content': item.content,
          'confidence': item.confidence,
        },
    ]);
  }

  Future<List<MemorySuggestion>> createSuggestions({
    required Map<String, String> realtimeStats,
    int limit = 4,
  }) async {
    assert(limit > 0);
    final all = await list();
    final activeTopics = all
        .where(
          (item) =>
              item.type == MemoryType.implicit &&
              item.status == MemoryStatus.active &&
              item.category == 'suggestion_topic' &&
              item.confidence >= _activeConfidence,
        )
        .toList();
    final disabled = all
        .where(
          (item) =>
              item.type == MemoryType.implicit &&
              item.status == MemoryStatus.disabled &&
              item.category == 'suggestion_topic',
        )
        .map((item) => item.content)
        .toSet();
    final used = <String>{};
    final result = <MemorySuggestion>[];
    for (final item in activeTopics) {
      final topic = item.content;
      final text = _topicTemplates[topic];
      if (text != null && used.add(topic)) {
        result.add(
          await _recordShown(text, topic, item.id, 'memory', realtimeStats),
        );
      }
      if (result.length == limit) return result;
    }
    for (final topic in _defaultTopics(realtimeStats)) {
      if (!disabled.contains(topic) && used.add(topic)) {
        result.add(
          await _recordShown(
            _topicTemplates[topic]!,
            topic,
            null,
            'default',
            realtimeStats,
          ),
        );
      }
      if (result.length == limit) break;
    }
    return result;
  }

  Future<void> recordSelected(MemorySuggestion suggestion) async {
    final db = await _db;
    final now = _now();
    final changed = await db.update(
      'recommendation_events',
      {'selected_at': now.toIso8601String()},
      where: 'id = ? AND selected_at IS NULL',
      whereArgs: [suggestion.eventId],
    );
    if (changed == 0) return;
    await _updateTopic(
      suggestion.topic,
      suggestion.memoryId,
      support: true,
      disable: false,
      eventId: suggestion.eventId,
    );
  }

  Future<void> recordFeedback(
    MemorySuggestion suggestion, {
    required bool disableTopic,
  }) async {
    final db = await _db;
    final now = _now();
    final changed = await db.update(
      'recommendation_events',
      {
        'feedback_at': now.toIso8601String(),
        'feedback_type': disableTopic ? 'disable_topic' : 'not_suitable',
      },
      where: 'id = ? AND feedback_at IS NULL',
      whereArgs: [suggestion.eventId],
    );
    if (changed == 0) return;
    await _updateTopic(
      suggestion.topic,
      suggestion.memoryId,
      support: false,
      disable: disableTopic,
      eventId: suggestion.eventId,
    );
  }

  Future<void> _updateTopic(
    String topic,
    String? id, {
    required bool support,
    required bool disable,
    required String eventId,
  }) async {
    final all = await list();
    MemoryItem? item;
    for (final candidate in all) {
      if (candidate.id == id ||
          (candidate.type == MemoryType.implicit &&
              candidate.category == 'suggestion_topic' &&
              candidate.content == topic)) {
        item = candidate;
        break;
      }
    }
    final now = _now();
    final db = await _db;
    if (item == null) {
      final created = await _add(
        type: MemoryType.implicit,
        category: 'suggestion_topic',
        content: topic,
        confidence: support ? .62 : .20,
        source: MemorySource.recommendation,
        evidenceKind: support
            ? 'recommendation_selected'
            : 'recommendation_feedback',
        evidenceReferenceId: eventId,
        evidenceSummary: support
            ? '用户选择了这类首页建议'
            : (disable ? '用户不再希望看到这类首页建议' : '用户认为这类首页建议不适合'),
      );
      if (disable) await setStatus(created.id, MemoryStatus.disabled);
      return;
    }
    final existing = item;
    final confidence = (existing.confidence + (support ? .08 : -.18))
        .clamp(.20, .95)
        .toDouble();
    await db.transaction((txn) async {
      await txn.update(
        'memory_items',
        {
          'confidence': confidence,
          'status': disable
              ? MemoryStatus.disabled.name
              : (confidence < .35
                    ? MemoryStatus.inactive.name
                    : existing.status.name),
          'last_confirmed_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [existing.id],
      );
      await txn.insert(
        'memory_evidence',
        _evidenceToRow(
          MemoryEvidence(
            id: newSumiId('evidence'),
            memoryId: existing.id,
            kind: support
                ? 'recommendation_selected'
                : 'recommendation_feedback',
            referenceId: eventId,
            summary: support
                ? '用户选择了这类首页建议'
                : (disable ? '用户不再希望看到这类首页建议' : '用户认为这类首页建议不适合'),
            occurredAt: now,
          ),
        ),
      );
    });
  }

  Future<MemorySuggestion> _recordShown(
    String text,
    String topic,
    String? memoryId,
    String source,
    Map<String, String> stats,
  ) async {
    await ensureTables();
    final id = newSumiId('rec');
    await (await _db).insert('recommendation_events', {
      'id': id,
      'text': text,
      'topic': topic,
      'memory_id': memoryId,
      'shown_at': _now().toIso8601String(),
      'context_json': jsonEncode(stats),
    });
    return MemorySuggestion(
      eventId: id,
      text: text,
      topic: topic,
      memoryId: memoryId,
      source: source,
    );
  }

  Future<void> importLegacyHypotheses() async {
    await ensureTables();
    final db = await _db;
    final state = await db.query(
      'memory_migration_state',
      where: 'key = ?',
      whereArgs: ['v13_hypotheses'],
      limit: 1,
    );
    if (state.isNotEmpty) return;
    try {
      final rows = await db.query('user_hypotheses');
      for (final row in rows) {
        if (row['kind'] != 'suggestionTopic') continue;
        final claim = jsonDecode(
          (row['claim_json'] as String?) ?? '{}',
        ) as Map<String, dynamic>;
        final topic = claim['topic'] as String?;
        if (topic == null || !_topicTemplates.containsKey(topic)) continue;
        final memory = await _add(
          type: MemoryType.implicit,
          category: 'suggestion_topic',
          content: topic,
          confidence: ((row['confidence'] as num?) ?? .2).toDouble(),
          source: MemorySource.recommendation,
          evidenceKind: 'legacy_hypothesis',
          evidenceSummary: '从旧版建议反馈迁移',
        );
        await db.update(
          'recommendation_events',
          {'memory_id': memory.id},
          where: 'topic = ? AND memory_id IS NULL',
          whereArgs: [topic],
        );
      }
      await db.execute('DROP TABLE IF EXISTS user_hypotheses');
    } catch (_) {
      // Older installations may not have the removed table.
    }
    await db.insert('memory_migration_state', {
      'key': 'v13_hypotheses',
      'value': 'done',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> importLegacyMarkdown(String content) async {
    await ensureTables();
    final db = await _db;
    final exists = await db.query(
      'memory_migration_state',
      where: 'key = ?',
      whereArgs: ['v13_markdown'],
      limit: 1,
    );
    if (exists.isNotEmpty || content.trim().isEmpty) return;
    final entries = RegExp(r'^-\\s+(?:\\[[^]]+\\]\\s+)?(.+)$', multiLine: true)
        .allMatches(content)
        .map((match) => match.group(1)!.trim())
        .where((entry) => entry.isNotEmpty);
    for (final entry in entries) {
      await _add(
        type: MemoryType.imported,
        category: 'legacy',
        content: entry,
        confidence: 0,
        source: MemorySource.legacy,
        evidenceKind: 'legacy_markdown',
        evidenceSummary: '从旧 USER_MODEL.md 导入',
      );
    }
    await db.insert('memory_migration_state', {
      'key': 'v13_markdown',
      'value': 'done',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> exportUserModel() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = io.File('${dir.path}/sumi/USER_MODEL.md');
      await file.parent.create(recursive: true);
      final items = await list();
      String block(String title, Iterable<MemoryItem> selected) =>
          '## $title\\n${selected.map((item) => '- ${item.content}').join('\\n')}\\n';
      final text =
          '# Sumi 对你的记忆\\n\\n${block('正在关注', items.where((item) => item.type == MemoryType.current && item.status == MemoryStatus.active))}\\n${block('明确记忆', items.where((item) => item.type == MemoryType.explicit && item.status == MemoryStatus.active))}\\n${block('里程碑', items.where((item) => item.type == MemoryType.milestone && item.status == MemoryStatus.active))}';
      await file.writeAsString(text);
    } catch (_) {
      // Export is compatibility-only; SQLite remains the source of truth.
    }
  }

  Future<void> clearAll() async {
    await ensureTables();
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('memory_evidence');
      await txn.delete('memory_items');
      await txn.delete('recommendation_events');
      await txn.delete('memory_migration_state');
      await txn.delete('memory_extraction_runs');
    });
    await exportUserModel();
  }

  List<String> _defaultTopics(Map<String, String> stats) {
    final topics = <String>['plan', 'priority', 'review', 'method', 'resource'];
    if (RegExp(r'^[1-9]').hasMatch(stats['planDeviationRate'] ?? '')) {
      topics.insert(0, 'adjust');
    }
    if (RegExp(r'^[0-5]').hasMatch(stats['weeklyCompletionRate'] ?? '')) {
      topics.insert(1, 'progress');
    }
    return topics;
  }

  int _matchScore(String query, String haystack) {
    if (query.isEmpty) return 0;
    if (haystack.contains(query)) return query.length;
    final words = query.split(RegExp(r'\\s+')).where((word) => word.isNotEmpty);
    var score = words.where(haystack.contains).length;
    if (score > 0) return score;
    for (final code in query.codeUnits.toSet()) {
      if (haystack.codeUnits.contains(code)) score++;
    }
    return score;
  }

  MemoryItem _itemFromRow(Map<String, Object?> row) => MemoryItem(
    id: row['id'] as String,
    type: MemoryType.values.firstWhere(
      (value) => value.name == row['type'],
      orElse: () => MemoryType.imported,
    ),
    category: (row['category'] as String?) ?? '',
    content: (row['content'] as String?) ?? '',
    projectId: row['project_id'] as String?,
    status: MemoryStatus.values.firstWhere(
      (value) => value.name == row['status'],
      orElse: () => MemoryStatus.inactive,
    ),
    confidence: ((row['confidence'] as num?) ?? 0).toDouble(),
    source: MemorySource.values.firstWhere(
      (value) => value.name == row['source'],
      orElse: () => MemorySource.legacy,
    ),
    replacesId: row['replaces_id'] as String?,
    createdAt:
        DateTime.tryParse((row['created_at'] as String?) ?? '') ?? _now(),
    lastConfirmedAt: DateTime.tryParse(
      (row['last_confirmed_at'] as String?) ?? '',
    ),
  );
  MemoryEvidence _evidenceFromRow(Map<String, Object?> row) => MemoryEvidence(
    id: row['id'] as String,
    memoryId: row['memory_id'] as String,
    kind: row['kind'] as String,
    referenceId: row['reference_id'] as String?,
    summary: (row['summary'] as String?) ?? '',
    occurredAt:
        DateTime.tryParse((row['occurred_at'] as String?) ?? '') ?? _now(),
  );
  Map<String, Object?> _itemToRow(MemoryItem item) => {
    'id': item.id,
    'type': item.type.name,
    'category': item.category,
    'content': item.content,
    'project_id': item.projectId,
    'status': item.status.name,
    'confidence': item.confidence,
    'source': item.source.name,
    'replaces_id': item.replacesId,
    'created_at': item.createdAt.toIso8601String(),
    'last_confirmed_at': item.lastConfirmedAt?.toIso8601String(),
  };
  Map<String, Object?> _evidenceToRow(MemoryEvidence evidence) => {
    'id': evidence.id,
    'memory_id': evidence.memoryId,
    'kind': evidence.kind,
    'reference_id': evidence.referenceId,
    'summary': evidence.summary,
    'occurred_at': evidence.occurredAt.toIso8601String(),
    'created_at': _now().toIso8601String(),
  };
}
