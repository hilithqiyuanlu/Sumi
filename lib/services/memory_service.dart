import 'dart:convert';
import 'dart:io' as io;

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../data/local_database.dart';
import '../utils/utils.dart';
import 'memory_extraction.dart';

enum MemoryType { explicit, current, implicit, imported }

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
  static const _activeConfidence = .70;
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
      decision_json TEXT, processed_at TEXT NOT NULL)''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_extraction_runs_processed ON memory_extraction_runs(processed_at)',
    );
    await _ensureRecommendationColumn(db);
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

  static const _currentExpiry = Duration(days: 30);

  Future<List<MemoryExtractionCandidate>> extractionCandidates({
    String? projectId,
    int limit = 6,
  }) async {
    await ensureTables();
    await expireStaleCurrent();
    final rows = await (await _db).query(
      'memory_items',
      where: '''status = ? AND (type = ? OR (type = ? AND project_id = ?))''',
      whereArgs: [
        MemoryStatus.active.name,
        MemoryType.explicit.name,
        MemoryType.current.name,
        projectId ?? '',
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
            projectId: item.projectId,
          );
        })
        .toList(growable: false);
  }

  /// Claims a persisted message for exactly one background extraction run.
  Future<bool> claimExtraction(String messageId) async {
    await ensureTables();
    try {
      await (await _db).insert('memory_extraction_runs', {
        'message_id': messageId,
        'status': 'pending',
        'processed_at': _now().toIso8601String(),
      });
      return true;
    } on DatabaseException {
      return false;
    }
  }

  Future<void> finishExtraction(
    String messageId, {
    required String status,
    MemoryExtractionDecision? decision,
  }) async {
    await ensureTables();
    await (await _db).update(
      'memory_extraction_runs',
      {
        'status': status,
        'decision_json': decision == null
            ? null
            : jsonEncode(decision.toJson()),
        'processed_at': _now().toIso8601String(),
      },
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  /// Applies a model decision only after validating every field against the
  /// persisted message boundary. Invalid decisions are kept as failed runs.
  Future<bool> applyExtractionDecision({
    required String messageId,
    required String userMessage,
    required MemoryExtractionDecision decision,
    required Set<String> candidateReplaceIds,
    String? currentProjectId,
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
    if (!valid.contains(category) ||
        content.length < 2 ||
        content.length > 200 ||
        quote.isEmpty ||
        quote.length > 500 ||
        !userMessage.contains(quote)) {
      await finishExtraction(messageId, status: 'failed', decision: decision);
      return false;
    }
    final replaceId = decision.replacesId?.trim();
    if ((decision.action == MemoryExtractionAction.replace &&
            (replaceId == null || !candidateReplaceIds.contains(replaceId))) ||
        (decision.action == MemoryExtractionAction.save && replaceId != null)) {
      await finishExtraction(messageId, status: 'failed', decision: decision);
      return false;
    }
    if (isCurrent && (currentProjectId == null || currentProjectId.isEmpty)) {
      await finishExtraction(messageId, status: 'failed', decision: decision);
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
            where:
                'type = ? AND project_id = ? AND category = ? AND status = ?',
            whereArgs: [
              MemoryType.current.name,
              currentProjectId,
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
            'project_id': isCurrent ? currentProjectId : null,
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
      await finishExtraction(messageId, status: 'failed', decision: decision);
      return false;
    }
  }

  Future<MemoryItem> addExplicit({
    MemoryType type = MemoryType.explicit,
    required String category,
    required String content,
    required String quotedText,
    required String messageId,
    String? projectId,
    String? replacesId,
  }) => _add(
    type: type,
    category: category,
    content: content,
    projectId: projectId,
    confidence: 1,
    source: MemorySource.userMessage,
    replacesId: replacesId,
    evidenceKind: 'user_message',
    evidenceReferenceId: messageId,
    evidenceSummary: quotedText,
  );

  Future<MemoryItem> addManual({
    required MemoryType type,
    required String category,
    required String content,
    String? projectId,
  }) {
    assert(type == MemoryType.explicit || type == MemoryType.current);
    return _add(
      type: type,
      category: category,
      content: content,
      projectId: projectId,
      confidence: 1,
      source: MemorySource.manual,
      evidenceKind: 'manual',
      evidenceSummary: '用户在记忆中心添加',
    );
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
    return item;
  }

  Future<void> update(
    String id, {
    required String category,
    required String content,
    String? projectId,
  }) async {
    await ensureTables();
    await (await _db).update(
      'memory_items',
      {
        'category': category.trim(),
        'content': content.trim(),
        'project_id': projectId,
        'last_confirmed_at': _now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
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

  Future<void> endCurrentForProject(String projectId) async {
    await ensureTables();
    await (await _db).update(
      'memory_items',
      {'status': MemoryStatus.inactive.name},
      where: 'type = ? AND project_id = ? AND status = ?',
      whereArgs: [MemoryType.current.name, projectId, MemoryStatus.active.name],
    );
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
    String? projectId,
    int limit = 8,
    Map<String, double> semanticScores = const {},
  }) async {
    await expireStaleCurrent();
    final normalized = query.trim().toLowerCase();
    final candidates = await list(includeHistorical: false);
    final scored = candidates
        .where((item) {
          return item.type != MemoryType.imported &&
              !(item.type == MemoryType.implicit &&
                  item.confidence < _activeConfidence) &&
              (projectId == null ||
                  item.projectId == null ||
                  item.projectId == projectId);
        })
        .map((item) {
          final topicText = item.category == 'suggestion_topic'
              ? (_topicTemplates[item.content] ?? '')
              : '';
          final haystack = '${item.category} ${item.content} $topicText'
              .toLowerCase();
          final keywordScore = _matchScore(normalized, haystack);
          final semanticScore = semanticScores[item.id] ?? 0;
          final projectBoost = projectId != null && item.projectId == projectId
              ? 2.5
              : 0;
          final typePriority = switch (item.type) {
            MemoryType.current => 3.5,
            MemoryType.explicit => 3.0,
            MemoryType.implicit => .5,
            MemoryType.imported => 0.0,
          };
          final categoryPriority = item.category == 'constraint' ? 1.5 : 0.0;
          final isRelevant =
              normalized.isEmpty ||
              keywordScore > 0 ||
              semanticScore >= .35 ||
              (projectId != null &&
                  item.projectId == projectId &&
                  item.type == MemoryType.current);
          return (
            item: item,
            isRelevant: isRelevant,
            score:
                (keywordScore * 1.2) +
                (semanticScore * 5) +
                projectBoost +
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
    String? projectId,
    Map<String, double> semanticScores = const {},
  }) => search(
    query,
    projectId: projectId,
    limit: 4,
    semanticScores: semanticScores,
  );

  Future<String> formatForAgent(
    String query, {
    String? projectId,
    int limit = 8,
    Map<String, double> semanticScores = const {},
  }) async {
    final items = await search(
      query,
      projectId: projectId,
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
          if (item.projectId != null) 'projectId': item.projectId,
          'confidence': item.confidence,
        },
    ]);
  }

  Future<List<MemorySuggestion>> createSuggestions({
    required Map<String, String> realtimeStats,
  }) async {
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
      if (result.length == 4) return result;
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
      if (result.length == 4) break;
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
          '# Sumi 对你的记忆\\n\\n${block('正在关注', items.where((item) => item.type == MemoryType.current && item.status == MemoryStatus.active))}\\n${block('明确记忆', items.where((item) => item.type == MemoryType.explicit && item.status == MemoryStatus.active))}\\n${block('系统从反馈中学到的', items.where((item) => item.type == MemoryType.implicit && item.status == MemoryStatus.active))}';
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
    final topics = <String>['plan', 'priority', 'review', 'method'];
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
