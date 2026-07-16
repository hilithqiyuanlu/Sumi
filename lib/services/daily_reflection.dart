import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../data/chat_database.dart';
import '../data/local_database.dart';
import '../data/signal_database.dart';
import '../models/models.dart';
import '../utils/utils.dart';
import 'memory_extraction.dart';
import 'memory_service.dart';
import 'model_router.dart';
import 'prompt_context.dart';

enum DailyReflectionStatus { pending, generating, ready, failed, skipped }

class DailyReflection {
  final String dateKey;
  final DailyReflectionStatus status;
  final String? shortSummary;
  final String? reflection;
  final List<String> highlights;
  final String? sourceFingerprint;
  final DateTime? attemptedAt;
  final DateTime? generatedAt;
  final String? failureCategory;
  final int automaticRetryCount;

  const DailyReflection({
    required this.dateKey,
    required this.status,
    this.shortSummary,
    this.reflection,
    this.highlights = const [],
    this.sourceFingerprint,
    this.attemptedAt,
    this.generatedAt,
    this.failureCategory,
    this.automaticRetryCount = 0,
  });
}

class DailyReflectionDatabase {
  final SumiLocalDatabase _store;
  bool _ensured = false;
  DailyReflectionDatabase(this._store);

  Future<Database> get _db => _store.database;

  Future<void> _ensureTables() async {
    if (_ensured) return;
    final db = await _db;
    await db.execute('''CREATE TABLE IF NOT EXISTS daily_reflections (
      date_key TEXT PRIMARY KEY, status TEXT NOT NULL, short_summary TEXT,
      reflection TEXT, highlights_json TEXT NOT NULL DEFAULT '[]',
      source_fingerprint TEXT, attempted_at TEXT, generated_at TEXT,
      failure_category TEXT,
      automatic_retry_count INTEGER NOT NULL DEFAULT 0
    )''');
    final columns = await db.rawQuery('PRAGMA table_info(daily_reflections)');
    if (!columns.any((column) => column['name'] == 'automatic_retry_count')) {
      await db.execute(
        'ALTER TABLE daily_reflections '
        'ADD COLUMN automatic_retry_count INTEGER NOT NULL DEFAULT 0',
      );
    }
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS daily_reflection_memory_runs (
      date_key TEXT PRIMARY KEY, status TEXT NOT NULL, updated_at TEXT NOT NULL
    )''',
    );
    _ensured = true;
  }

  Future<DailyReflection?> get(String date) async {
    await _ensureTables();
    final rows = await (await _db).query(
      'daily_reflections',
      where: 'date_key = ?',
      whereArgs: [date],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  Future<void> save(DailyReflection value) async {
    await _ensureTables();
    await (await _db).insert(
      'daily_reflections',
      _toRow(value),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearAll() async {
    await _ensureTables();
    final db = await _db;
    await db.delete('daily_reflections');
    await db.delete('daily_reflection_memory_runs');
  }

  Future<void> delete(String date) async {
    await _ensureTables();
    await (await _db).delete(
      'daily_reflections',
      where: 'date_key = ?',
      whereArgs: [date],
    );
  }

  /// 返回 true 代表本日尚未成功补漏，可以开始一次新的处理。
  Future<bool> beginMemoryRun(String date) async {
    await _ensureTables();
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query(
      'daily_reflection_memory_runs',
      where: 'date_key = ?',
      whereArgs: [date],
      limit: 1,
    );
    if (rows.isEmpty) {
      await db.insert('daily_reflection_memory_runs', {
        'date_key': date,
        'status': 'pending',
        'updated_at': now,
      });
      return true;
    }
    final status = rows.single['status'] as String? ?? '';
    if (status == 'applied' || status == 'ignored' || status == 'pending') {
      return false;
    }
    await db.update(
      'daily_reflection_memory_runs',
      {'status': 'pending', 'updated_at': now},
      where: 'date_key = ?',
      whereArgs: [date],
    );
    return true;
  }

  Future<void> finishMemoryRun(String date, String status) async {
    await (await _db).update(
      'daily_reflection_memory_runs',
      {'status': status, 'updated_at': DateTime.now().toIso8601String()},
      where: 'date_key = ?',
      whereArgs: [date],
    );
  }

  DailyReflection _fromRow(Map<String, Object?> row) {
    final rawHighlights = row['highlights_json'] as String? ?? '[]';
    List<String> highlights;
    try {
      highlights = (jsonDecode(rawHighlights) as List)
          .whereType<String>()
          .toList(growable: false);
    } catch (_) {
      highlights = const [];
    }
    return DailyReflection(
      dateKey: row['date_key'] as String,
      status: DailyReflectionStatus.values.firstWhere(
        (value) => value.name == row['status'],
        orElse: () => DailyReflectionStatus.pending,
      ),
      shortSummary: row['short_summary'] as String?,
      reflection: row['reflection'] as String?,
      highlights: highlights,
      sourceFingerprint: row['source_fingerprint'] as String?,
      attemptedAt: DateTime.tryParse(row['attempted_at'] as String? ?? ''),
      generatedAt: DateTime.tryParse(row['generated_at'] as String? ?? ''),
      failureCategory: row['failure_category'] as String?,
      automaticRetryCount: (row['automatic_retry_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, Object?> _toRow(DailyReflection value) => {
    'date_key': value.dateKey,
    'status': value.status.name,
    'short_summary': value.shortSummary,
    'reflection': value.reflection,
    'highlights_json': jsonEncode(value.highlights),
    'source_fingerprint': value.sourceFingerprint,
    'attempted_at': value.attemptedAt?.toIso8601String(),
    'generated_at': value.generatedAt?.toIso8601String(),
    'failure_category': value.failureCategory,
    'automatic_retry_count': value.automaticRetryCount,
  };
}

class DailyReflectionService {
  final DailyReflectionDatabase database;
  final ChatDatabase chat;
  final SignalDatabase signals;
  final StructuredGenerationCapability? Function() structuredAi;
  final MemoryService memory;
  final MemoryExtractionCapability? Function() memoryAi;
  final void Function() onChanged;
  final void Function() onMemoryChanged;
  final DateTime Function() now;
  bool _running = false;
  final _activeGenerations = <String>{};
  static const _generatingTimeoutMinutes = 2;
  static const _automaticRetryDelay = Duration(seconds: 3);

  DailyReflectionService({
    required this.database,
    required this.chat,
    required this.signals,
    required this.structuredAi,
    required this.memory,
    required this.memoryAi,
    required this.onChanged,
    required this.onMemoryChanged,
    required this.now,
  });

  Future<DailyReflection?> reflectionFor(DateTime date) =>
      database.get(dateKey(dateOnly(date)));

  /// 登记用户刚查看的过去日期；无有效内容时只标记 skipped，不显示组件。
  Future<void> ensureForDate(DateTime date) async {
    try {
      await _ensureForDate(date);
    } catch (_) {
      // 这是非阻塞后台工作；应用关闭或数据库销毁时直接放弃即可。
    }
  }

  Future<void> _ensureForDate(DateTime date) async {
    final key = dateKey(dateOnly(date));
    if (key.compareTo(dateKey(dateOnly(now()))) >= 0) return;
    final existing = await database.get(key);
    if (existing != null) return;
    final input = await _loadInput(key);
    if (!input.hasContent) {
      await database.save(
        DailyReflection(dateKey: key, status: DailyReflectionStatus.skipped),
      );
      return;
    }
    await database.save(
      DailyReflection(dateKey: key, status: DailyReflectionStatus.pending),
    );
    onChanged();
    unawaited(runBacklog(preferredDate: key));
  }

  /// 从最早未处理有效日期起补跑，单次严格不超过两天。
  Future<void> runBacklog({String? preferredDate}) async {
    if (_running || structuredAi() == null) return;
    _running = true;
    try {
      final today = dateKey(dateOnly(now()));
      final dates = <String>{
        ...await chat.pastConversationDates(beforeDate: today),
        ...await signals.pastSignalDates(beforeDate: today),
      }.where((date) => date.compareTo(today) < 0).toList()..sort();
      if (preferredDate != null && dates.remove(preferredDate)) {
        dates.insert(0, preferredDate);
      }
      var processed = 0;
      for (final date in dates) {
        if (processed >= 2) break;
        final existing = await database.get(date);
        if (existing?.status == DailyReflectionStatus.ready) {
          final input = await _loadInput(date);
          await _backfillMemory(date, input.userMessages);
          continue;
        }
        if (existing?.status == DailyReflectionStatus.skipped) {
          continue;
        }
        if (existing != null &&
            existing.status == DailyReflectionStatus.failed) {
          if (!_canAutomaticallyRetry(existing)) continue;
          await generate(date, retry: true, automaticRetry: true);
          processed++;
          continue;
        }
        if (existing?.status == DailyReflectionStatus.generating) {
          final attemptedAt = existing?.attemptedAt;
          if (attemptedAt != null &&
              now().difference(attemptedAt).inMinutes <
                  _generatingTimeoutMinutes) {
            continue;
          }
          // 超时认为已中断，重置为 pending 继续处理。
          await database.save(
            DailyReflection(
              dateKey: date,
              status: DailyReflectionStatus.pending,
            ),
          );
        }
        await generate(date);
        processed++;
      }
    } catch (_) {
      // 启动补跑不应影响应用启动；下一次启动会从未处理日期继续。
    } finally {
      _running = false;
    }
  }

  Future<void> retry(String date) async {
    final existing = await database.get(date);
    if (existing == null || existing.status == DailyReflectionStatus.ready) {
      return;
    }
    // 允许对 pending / generating / failed 状态重新触发。
    await generate(
      date,
      retry: existing.status == DailyReflectionStatus.failed,
    );
  }

  Future<void> regenerate(String date) async {
    if (_activeGenerations.contains(date)) return;
    await database.delete(date);
    onChanged();
    await generate(date);
  }

  Future<void> remove(String date) async {
    await database.delete(date);
    onChanged();
  }

  Future<void> generate(
    String date, {
    bool retry = false,
    bool automaticRetry = false,
  }) async {
    if (_activeGenerations.contains(date)) return;
    _activeGenerations.add(date);
    var retryAutomatically = false;
    try {
      final capability = structuredAi();
      if (capability == null) return;
      final existing = await database.get(date);
      if (existing?.status == DailyReflectionStatus.ready) return;
      if (existing?.status == DailyReflectionStatus.failed && !retry) return;
      final automaticRetryCount = existing?.automaticRetryCount ?? 0;
      final input = await _loadInput(date);
      if (!input.hasContent) {
        await database.save(
          DailyReflection(dateKey: date, status: DailyReflectionStatus.skipped),
        );
        onChanged();
        return;
      }
      final fingerprint = sha256
          .convert(utf8.encode(jsonEncode(input.forFingerprint)))
          .toString();
      await database.save(
        DailyReflection(
          dateKey: date,
          status: DailyReflectionStatus.generating,
          sourceFingerprint: fingerprint,
          attemptedAt: now(),
        ),
      );
      onChanged();
      try {
        final result = await capability.generateDailyReflection(
          date: date,
          messages: input.messagesForAi,
          signals: input.signalsForAi,
        );
        if (result == null) {
          final error = capability.lastError;
          await _saveFailure(
            date,
            fingerprint,
            error,
            automaticRetryCount: automaticRetry
                ? automaticRetryCount + 1
                : automaticRetryCount,
          );
          retryAutomatically =
              !automaticRetry &&
              automaticRetryCount == 0 &&
              _isRecoverableFailure(error);
        } else {
          await database.save(
            DailyReflection(
              dateKey: date,
              status: DailyReflectionStatus.ready,
              shortSummary: result.shortSummary,
              reflection: result.reflection,
              highlights: result.highlights,
              sourceFingerprint: fingerprint,
              attemptedAt: now(),
              generatedAt: now(),
            ),
          );
          onChanged();
          try {
            await _backfillMemory(date, input.userMessages);
          } catch (error) {
            // memory backfill 不应影响已生成总结的可展示性。
            debugPrint('[_backfillMemory] $date failed: $error');
          }
        }
      } catch (error) {
        await _saveFailure(
          date,
          fingerprint,
          error.toString(),
          automaticRetryCount: automaticRetry
              ? automaticRetryCount + 1
              : automaticRetryCount,
        );
        retryAutomatically =
            !automaticRetry &&
            automaticRetryCount == 0 &&
            _isRecoverableFailure(error.toString());
      }
    } finally {
      _activeGenerations.remove(date);
    }
    if (!retryAutomatically) return;
    await Future<void>.delayed(_automaticRetryDelay);
    final latest = await database.get(date);
    if (latest?.status != DailyReflectionStatus.failed ||
        latest?.automaticRetryCount != 0) {
      return;
    }
    await generate(date, retry: true, automaticRetry: true);
  }

  Future<void> _saveFailure(
    String date,
    String fingerprint,
    String? error, {
    required int automaticRetryCount,
  }) async {
    await database.save(
      DailyReflection(
        dateKey: date,
        status: DailyReflectionStatus.failed,
        sourceFingerprint: fingerprint,
        attemptedAt: now(),
        failureCategory: ModelRouterErrorClassifier.fromMessage(
          error ?? '',
        ).name,
        automaticRetryCount: automaticRetryCount,
      ),
    );
    onChanged();
  }

  bool _canAutomaticallyRetry(DailyReflection reflection) {
    if (reflection.automaticRetryCount >= 1) return false;
    final attemptedAt = reflection.attemptedAt;
    if (attemptedAt != null &&
        now().difference(attemptedAt) < _automaticRetryDelay) {
      return false;
    }
    return _isRecoverableFailure(reflection.failureCategory);
  }

  bool _isRecoverableFailure(String? error) {
    final category = ModelRouterErrorCategory.values.firstWhere(
      (value) => value.name == error,
      orElse: () => ModelRouterErrorClassifier.fromMessage(error ?? ''),
    );
    return switch (category) {
      ModelRouterErrorCategory.network ||
      ModelRouterErrorCategory.timeout ||
      ModelRouterErrorCategory.rateLimited ||
      ModelRouterErrorCategory.validation ||
      ModelRouterErrorCategory.unknown => true,
      ModelRouterErrorCategory.none ||
      ModelRouterErrorCategory.authentication ||
      ModelRouterErrorCategory.unavailable => false,
    };
  }

  Future<void> _backfillMemory(
    String date,
    List<ChatMessage> userMessages,
  ) async {
    final extractor = memoryAi();
    if (extractor == null ||
        userMessages.isEmpty ||
        !await database.beginMemoryRun(date)) {
      return;
    }
    try {
      final candidates = await memory.extractionCandidates(limit: 8);
      for (final message in userMessages) {
        if (await memory.hasUserMessageEvidence(message.id)) {
          continue;
        }
        final decision = await extractor.extractMemory(
          message: message.content,
          candidates: candidates,
        );
        if (decision == null ||
            decision.action != MemoryExtractionAction.save ||
            decision.type != MemoryType.explicit) {
          continue;
        }
        if (await memory.applyDailyBackfillDecision(
          messageId: message.id,
          userMessage: message.content,
          decision: decision,
        )) {
          await memory.exportUserModel();
          onMemoryChanged();
          await database.finishMemoryRun(date, 'applied');
          return;
        }
      }
      await database.finishMemoryRun(date, 'ignored');
    } catch (_) {
      await database.finishMemoryRun(date, 'failed');
    }
  }

  Future<_DailyInput> _loadInput(String date) async {
    final messages = await chat.loadMessagesForDate(date);
    final useful = messages
        .where((message) {
          if (message.role != 'user' && message.role != 'assistant') {
            return false;
          }
          return message.content.trim().isNotEmpty;
        })
        .toList(growable: false);
    final signalsForDay = await signals.queryDate(date);
    return _DailyInput(useful, signalsForDay);
  }
}

class _DailyInput {
  final List<ChatMessage> messages;
  final List<UserSignal> signals;
  const _DailyInput(this.messages, this.signals);

  bool get hasContent => messages.isNotEmpty || signals.isNotEmpty;
  List<ChatMessage> get userMessages => messages
      .where((message) => message.role == 'user')
      .toList(growable: false);

  List<Map<String, Object?>> get messagesForAi {
    const maxMessages = 24;
    const maxCharacters = 8000;
    var remaining = maxCharacters;
    final latest = messages.length <= maxMessages
        ? messages
        : messages.sublist(messages.length - maxMessages);
    final result = <Map<String, Object?>>[];
    for (final message in latest) {
      if (remaining <= 0) break;
      final content = message.content.trim();
      final bounded = content.length <= remaining
          ? content
          : content.substring(0, remaining);
      remaining -= bounded.length;
      result.add({'role': message.role, 'content': bounded});
    }
    return result;
  }

  List<Map<String, Object?>> get signalsForAi => signals
      .take(40)
      .map(
        (signal) => {
          'signal': signal.signal.name,
          'time': signal.time.toIso8601String(),
          'context': PromptContext.truncate(
            jsonEncode(SignalDatabase.contextForAi(signal)),
            400,
          ),
        },
      )
      .toList(growable: false);

  Map<String, Object?> get forFingerprint => {
    'messages': messages
        .map(
          (message) => {
            'id': message.id,
            'role': message.role,
            'content': message.content,
          },
        )
        .toList(growable: false),
    'signals': signalsForAi,
  };
}
