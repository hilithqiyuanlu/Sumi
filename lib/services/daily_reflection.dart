import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../data/chat_database.dart';
import '../data/local_database.dart';
import '../data/signal_database.dart';
import '../models/models.dart';
import '../utils/utils.dart';
import 'memory_extraction.dart';
import 'memory_service.dart';
import 'model_router.dart';

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
      failure_category TEXT
    )''');
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
        if (existing?.status == DailyReflectionStatus.skipped ||
            existing?.status == DailyReflectionStatus.generating ||
            existing?.status == DailyReflectionStatus.failed) {
          continue;
        }
        await generate(
          date,
          retry: existing?.status == DailyReflectionStatus.failed,
        );
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
    if (existing?.status != DailyReflectionStatus.failed) return;
    await generate(date, retry: true);
  }

  Future<void> generate(String date, {bool retry = false}) async {
    final capability = structuredAi();
    if (capability == null) return;
    final existing = await database.get(date);
    if (existing?.status == DailyReflectionStatus.ready ||
        existing?.status == DailyReflectionStatus.generating ||
        (existing?.status == DailyReflectionStatus.failed && !retry)) {
      return;
    }
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
        await _saveFailure(date, fingerprint, capability.lastError);
        return;
      }
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
      await _backfillMemory(date, input.userMessages);
    } catch (error) {
      await _saveFailure(date, fingerprint, error.toString());
    }
  }

  Future<void> _saveFailure(
    String date,
    String fingerprint,
    String? error,
  ) async {
    await database.save(
      DailyReflection(
        dateKey: date,
        status: DailyReflectionStatus.failed,
        sourceFingerprint: fingerprint,
        attemptedAt: now(),
        failureCategory: ModelRouterErrorClassifier.fromMessage(
          error ?? '',
        ).name,
      ),
    );
    onChanged();
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

  List<Map<String, Object?>> get messagesForAi => messages
      .map(
        (message) => {'role': message.role, 'content': message.content.trim()},
      )
      .toList(growable: false);

  List<Map<String, Object?>> get signalsForAi => signals
      .map(
        (signal) => {
          'signal': signal.signal.name,
          'time': signal.time.toIso8601String(),
          'context': signal.context,
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
