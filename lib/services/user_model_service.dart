import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/signal_database.dart';
import '../data/local_database.dart';
import '../models/models.dart';
import 'memory_service.dart';
import 'package:sqflite/sqflite.dart';

enum UserModelStatus { observing, active, disabled }

class UserModelItem {
  final String id;
  final String kind;
  final String content;
  final double confidence;
  final UserModelStatus status;
  final String? sourceMemoryId;
  final DateTime createdAt;
  final DateTime? lastVerifiedAt;

  const UserModelItem({
    required this.id,
    required this.kind,
    required this.content,
    required this.confidence,
    required this.status,
    this.sourceMemoryId,
    required this.createdAt,
    this.lastVerifiedAt,
  });
}

class UserModelEvidence {
  final String kind;
  final String summary;
  final DateTime occurredAt;

  const UserModelEvidence({
    required this.kind,
    required this.summary,
    required this.occurredAt,
  });
}

class UserModelStore {
  final SumiLocalDatabase _store;
  final DateTime Function() _now;

  UserModelStore(this._store, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  Future<Database> get _db => _store.database;

  Future<void> ensureTables() async {
    final db = await _db;
    await db.execute('''CREATE TABLE IF NOT EXISTS user_model_items (
      id TEXT PRIMARY KEY, kind TEXT NOT NULL, content TEXT NOT NULL,
      confidence REAL NOT NULL, status TEXT NOT NULL, source_memory_id TEXT UNIQUE,
      created_at TEXT NOT NULL, last_verified_at TEXT)''');
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS user_model_evidence (
      id TEXT PRIMARY KEY, item_id TEXT NOT NULL, kind TEXT NOT NULL,
      reference_id TEXT, summary TEXT NOT NULL, occurred_at TEXT NOT NULL,
      FOREIGN KEY(item_id) REFERENCES user_model_items(id) ON DELETE CASCADE)''',
    );
  }

  Future<void> syncFromImplicit(MemoryService memory) async {
    await ensureTables();
    for (final source in await memory.list()) {
      if (source.type != MemoryType.implicit) continue;
      final status = source.status == MemoryStatus.disabled
          ? UserModelStatus.disabled
          : source.confidence >= .85
          ? UserModelStatus.active
          : UserModelStatus.observing;
      await (await _db).insert('user_model_items', {
        'id': 'model-${source.id}',
        'kind': source.category,
        'content': source.content,
        'confidence': source.confidence,
        'status': status.name,
        'source_memory_id': source.id,
        'created_at': source.createdAt.toIso8601String(),
        'last_verified_at': source.lastConfirmedAt?.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      for (final evidence in await memory.evidenceFor(source.id)) {
        await (await _db).insert('user_model_evidence', {
          'id': 'model-evidence-${source.id}-${evidence.id}',
          'item_id': 'model-${source.id}',
          'kind': evidence.kind,
          'reference_id': evidence.referenceId,
          'summary': evidence.summary,
          'occurred_at': evidence.occurredAt.toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  }

  Future<List<UserModelItem>> list() async {
    await ensureTables();
    final rows = await (await _db).query(
      'user_model_items',
      orderBy: 'status ASC, confidence DESC, last_verified_at DESC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<List<UserModelItem>> activeForSuggestions({int limit = 6}) async {
    await ensureTables();
    final rows = await (await _db).query(
      'user_model_items',
      where: 'status = ? AND confidence >= ?',
      whereArgs: [UserModelStatus.active.name, .85],
      orderBy: 'confidence DESC, last_verified_at DESC, created_at DESC',
      limit: limit,
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<List<UserModelEvidence>> evidenceFor(String id) async {
    await ensureTables();
    final rows = await (await _db).query(
      'user_model_evidence',
      where: 'item_id = ?',
      whereArgs: [id],
      orderBy: 'occurred_at DESC',
    );
    return rows
        .map(
          (row) => UserModelEvidence(
            kind: row['kind'] as String,
            summary: row['summary'] as String,
            occurredAt:
                DateTime.tryParse(row['occurred_at'] as String? ?? '') ??
                _now(),
          ),
        )
        .toList(growable: false);
  }

  Future<void> setStatus(String id, UserModelStatus status) async {
    await ensureTables();
    final db = await _db;
    final rows = await db.query(
      'user_model_items',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final sourceId = rows.single['source_memory_id'] as String?;
    await db.update(
      'user_model_items',
      {'status': status.name, 'last_verified_at': _now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (sourceId != null) {
      await db.update(
        'memory_items',
        {'status': status == UserModelStatus.disabled ? 'disabled' : 'active'},
        where: 'id = ?',
        whereArgs: [sourceId],
      );
    }
  }

  Future<void> delete(String id) async {
    await ensureTables();
    final db = await _db;
    final rows = await db.query(
      'user_model_items',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return;
    final sourceId = rows.single['source_memory_id'] as String?;
    await db.transaction((txn) async {
      await txn.delete(
        'user_model_evidence',
        where: 'item_id = ?',
        whereArgs: [id],
      );
      await txn.delete('user_model_items', where: 'id = ?', whereArgs: [id]);
      if (sourceId != null) {
        await txn.delete(
          'memory_evidence',
          where: 'memory_id = ?',
          whereArgs: [sourceId],
        );
        await txn.delete(
          'memory_items',
          where: 'id = ?',
          whereArgs: [sourceId],
        );
      }
    });
  }

  Future<void> clearAll() async {
    await ensureTables();
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('user_model_evidence');
      await txn.delete('user_model_items');
    });
  }

  UserModelItem _fromRow(Map<String, Object?> row) => UserModelItem(
    id: row['id'] as String,
    kind: row['kind'] as String,
    content: row['content'] as String,
    confidence: (row['confidence'] as num).toDouble(),
    status: UserModelStatus.values.firstWhere(
      (item) => item.name == row['status'],
      orElse: () => UserModelStatus.observing,
    ),
    sourceMemoryId: row['source_memory_id'] as String?,
    createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ?? _now(),
    lastVerifiedAt: DateTime.tryParse(row['last_verified_at'] as String? ?? ''),
  );
}

/// 合并操作结果。
class MergeResult {
  final String action; // "skip" | "replace" | "append" | "conflict"
  final String? mergedCoreMemory; // 合并后的核心记忆区全文
  final String message; // 反馈给 AI 的消息

  const MergeResult({
    required this.action,
    this.mergedCoreMemory,
    required this.message,
  });
}

/// 用户模型服务 —— USER_MODEL.md 读写、统计计算、记忆合并、prompt 拼接。
/// 替代旧 MEMORY.md 系统（07 轮新增）。
class UserModelService {
  final SignalDatabase _signalDb;

  UserModelService(this._signalDb);

  // ---------------------------------------------------------------------------
  // 文件 I/O
  // ---------------------------------------------------------------------------

  static const _fileName = 'USER_MODEL.md';

  Future<String> _filePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/sumi/$_fileName';
  }

  /// 读取 USER_MODEL.md 全文。
  Future<String> readUserModel() async {
    try {
      final file = io.File(await _filePath());
      if (!await file.exists()) return _defaultUserModel();
      return await file.readAsString();
    } catch (_) {
      return _defaultUserModel();
    }
  }

  /// 覆写 USER_MODEL.md 全文。
  Future<void> writeUserModel(String content) async {
    if (!isValidUserModel(content)) {
      throw const FormatException('USER_MODEL.md 缺少必要区段');
    }
    await _writeRaw(content);
  }

  Future<void> resetUserModel() => _writeRaw(defaultUserModel);

  Future<void> _writeRaw(String content) async {
    try {
      final path = await _filePath();
      final sepIdx = path.lastIndexOf('/');
      if (sepIdx != -1) {
        final dir = io.Directory(path.substring(0, sepIdx));
        if (!await dir.exists()) await dir.create(recursive: true);
      }
      await io.File(path).writeAsString(content);
    } catch (e) {
      debugPrint('[UserModelService] writeUserModel error: $e');
      rethrow;
    }
  }

  /// 将当前 USER_MODEL.md 复制为带时间戳的备份，返回备份路径。
  Future<String?> backupUserModel() async {
    try {
      final path = await _filePath();
      final file = io.File(path);
      if (!await file.exists()) return null;
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final backupPath = '$path.bak.$timestamp';
      await file.copy(backupPath);
      try {
        final backups = await file.parent
            .list()
            .where(
              (entry) =>
                  entry is io.File && entry.path.startsWith('$path.bak.'),
            )
            .cast<io.File>()
            .toList();
        backups.sort((a, b) => b.path.compareTo(a.path));
        for (final oldBackup in backups.skip(10)) {
          await oldBackup.delete();
        }
      } catch (e) {
        debugPrint('[UserModelService] 清理旧备份失败: $e');
      }
      return backupPath;
    } catch (e) {
      debugPrint('[UserModelService] backupUserModel error: $e');
      return null;
    }
  }

  /// 校验 USER_MODEL.md 内容是否包含关键区段结构。
  bool isValidUserModel(String content) {
    if (content.trim().isEmpty) return false;
    final required = [
      '## 核心记忆',
      '<!-- END CORE MEMORY -->',
      '## 长期偏好',
      '<!-- END PREFS -->',
      '## 领域画像',
      '<!-- END DOMAIN -->',
    ];
    for (final marker in required) {
      if (!content.contains(marker)) return false;
    }
    return true;
  }

  /// 向指定区段追加一条条目。
  Future<void> appendToSection(String section, String entry) async {
    final content = await readUserModel();
    final marker = _sectionMarker(section);
    if (marker == null) return;
    final updated = _appendUnderSection(content, marker, entry);
    await writeUserModel(updated);
  }

  /// 旧 MEMORY.md 迁移 → USER_MODEL.md。
  /// 将旧的平面时间线内容迁移到核心记忆区。
  Future<String> migrateFromLegacyMemory(String legacyContent) async {
    if (legacyContent.trim().isEmpty) return _defaultUserModel();

    // 去掉旧文件头部 "# Sumi MEMORY.md"
    var cleaned = legacyContent.trim();
    cleaned = cleaned.replaceFirst(RegExp(r'^#\s*Sumi MEMORY\.md\s*'), '');

    final defaultModel = _defaultUserModel();
    // 将旧记忆作为核心记忆的一部分插入
    final insertionPoint = defaultModel.indexOf('<!-- END CORE MEMORY -->');
    if (insertionPoint == -1) return defaultModel;

    // 从旧内容中提取 ### 记忆 YYYY-MM-DD... 条目
    final memories = cleaned.trim();
    final before = defaultModel.substring(0, insertionPoint);
    final after = defaultModel.substring(insertionPoint);

    var migrated = '$before\n\n## 历史迁移（来自 MEMORY.md）\n$memories\n\n$after';

    // 确保不超过 8 条核心记忆的硬限制——其余移到归档区
    final coreCount = '---'
        .allMatches(
          migrated.substring(
            migrated.indexOf('## 核心记忆'),
            migrated.indexOf('<!-- END CORE MEMORY -->'),
          ),
        )
        .length;
    if (coreCount > 8) {
      migrated = _moveExcessToArchive(migrated, 8);
    }

    return migrated;
  }

  // ---------------------------------------------------------------------------
  // 即时统计（规则计算，0 token）
  // ---------------------------------------------------------------------------

  /// 计算实时统计摘要，直接嵌入 USER_MODEL.md 的 SYSTEM-MANAGED 区块。
  Future<Map<String, String>> computeRealtimeStats() async {
    // 一次查询本周信号，内存中分类统计
    final weekSignals = await _signalDb.query(range: '7d', limit: 1000);
    final completed = weekSignals
        .where((s) => s.signal == SignalType.todoCompleted)
        .length;
    final created = weekSignals
        .where((s) => s.signal == SignalType.todoCreated)
        .length;
    final moved = weekSignals
        .where((s) => s.signal == SignalType.todoMovedDate)
        .length;
    final total = created > 0 ? created : 1;
    final rate = (completed * 100.0 / total).round();

    // 连续活跃天数
    final streak = await _activeStreak();

    // 主要活跃时段
    final hourly = await _signalDb.hourlyDistribution(days: 30);
    String primeTime = '9:00-11:00';
    if (hourly.length >= 2) {
      final h1 = hourly[0]['hour']!;
      final h2 = hourly[1]['hour']!;
      primeTime =
          '${h1.toString().padLeft(2, '0')}:00-${h2.toString().padLeft(2, '0')}:00';
    }

    // 活跃项目数（从本周信号中提取，复用 weekSignals）
    final projectIds = <String>{};
    for (final s in weekSignals) {
      if (s.projectId != null) projectIds.add(s.projectId!);
    }
    final activeProjects = projectIds.length;

    // 计划偏差率
    final deviation = total > 0 ? (moved * 100.0 / total).round() : 0;

    return {
      'weeklyCompletionRate': '$rate%（$completed/$total）',
      'streakDays': '$streak',
      'primeTimeWindow': primeTime,
      'activeProjectCount': '$activeProjects',
      'planDeviationRate': '$deviation%（$moved 次拖拽换日）',
    };
  }

  /// 计算连续活跃天数（从今天往前数，连续有信号的天数）。
  Future<int> _activeStreak() async {
    final signals = await _signalDb.query(range: 'all', limit: 2000);
    final activeDays = <String>{};
    for (final s in signals) {
      activeDays.add(
        '${s.time.year}-${s.time.month.toString().padLeft(2, '0')}-${s.time.day.toString().padLeft(2, '0')}',
      );
    }
    var streak = 0;
    for (var d = 0; d < 365; d++) {
      final day = DateTime.now().subtract(Duration(days: d));
      final dayStr =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      if (activeDays.contains(dayStr)) {
        streak++;
      } else if (d > 0) {
        break;
      }
    }
    return streak;
  }

  // ---------------------------------------------------------------------------
  // 系统管理区替换
  // ---------------------------------------------------------------------------

  static const _systemManagedSection = '''
## 实时状态
<!-- SYSTEM-MANAGED: 系统自动替换，不要手动编辑 -->
- 用户：{userName}
- 本周完成率：{weeklyCompletionRate}
- 连续活跃：{streakDays} 天
- 主要活跃时段：{primeTimeWindow}
- 当前活跃项目：{activeProjectCount} 个
- 计划偏差率：{planDeviationRate}
<!-- END SYSTEM-MANAGED -->''';

  String injectRealtimeStats(String fullContent, Map<String, String> stats) {
    final pattern = RegExp(
      r'<!-- SYSTEM-MANAGED:.*?-->.*?<!-- END SYSTEM-MANAGED -->',
      dotAll: true,
    );
    var newSection = _systemManagedSection;
    for (final entry in stats.entries) {
      newSection = newSection.replaceAll('{${entry.key}}', entry.value);
    }
    if (pattern.hasMatch(fullContent)) {
      return fullContent.replaceAll(pattern, newSection);
    }
    // 如果模板中没有该区块，在文件头部（# Sumi 对你的理解 之后）插入
    final titleMatch = RegExp(
      r'^# .*$',
      multiLine: true,
    ).firstMatch(fullContent);
    if (titleMatch != null) {
      return fullContent.replaceFirst(
        titleMatch.group(0)!,
        '${titleMatch.group(0)!}\n\n$newSection',
      );
    }
    return '$newSection\n\n$fullContent';
  }

  // ---------------------------------------------------------------------------
  // 按层 prompt 拼接
  // ---------------------------------------------------------------------------

  /// HOT 层：实时状态 + 最多 4 条用户明确的核心记忆。
  /// 行为推断存于本地假设表，不写入 Markdown。
  String buildHotPrompt(String fullContent) {
    final statsSection = _extractSection(fullContent, '实时状态');
    final coreSection = _extractSection(fullContent, '核心记忆');

    // 限制核心记忆条目数
    final trimmedCore = _trimCoreMemory(coreSection, 4);

    final buf = StringBuffer();
    buf.writeln(statsSection);
    if (trimmedCore.isNotEmpty) {
      buf.writeln(trimmedCore);
    }
    return buf.toString();
  }

  /// 仅供显式 read_memory 或规划使用，不在普通对话自动注入。
  String buildWarmPrefsPrompt(String fullContent) {
    return _extractSection(fullContent, '长期偏好');
  }

  /// 全文（周度反思用）。
  String buildFullPrompt(String fullContent) {
    return fullContent;
  }

  // ---------------------------------------------------------------------------
  // 记忆合并（Dice coefficient）
  // ---------------------------------------------------------------------------

  /// 判断新条目与已有核心记忆的关系并执行合并。
  /// - 相似度 > 90% → skip
  /// - 50-90% → replace（后缀 "(已更新)"）
  /// - 与[确信]条目矛盾 → append "[待确认]" + 标注
  /// - 全新 → append
  MergeResult mergeMemoryEntry(String newEntry, String existingCoreMemory) {
    if (newEntry.trim().isEmpty) {
      return const MergeResult(action: 'skip', message: '记忆内容为空，跳过写入。');
    }

    final entries = _parseCoreEntries(existingCoreMemory);

    if (entries.isEmpty) {
      return const MergeResult(action: 'append', message: '已写入新记忆。');
    }

    // 计算与已有条目的最高相似度
    var maxSim = 0.0;
    var bestMatch = '';
    var bestLabel = '';

    for (final entry in entries) {
      // 去掉置信度标记再比较
      final normalizedEntry = entry.replaceFirst(RegExp(r'^-\s*'), '');
      final strippedEntry = normalizedEntry.replaceFirst(
        RegExp(r'^\[.*?\]\s*'),
        '',
      );
      final sim = _diceCoefficient(newEntry, strippedEntry);
      if (sim > maxSim) {
        maxSim = sim;
        bestMatch = entry;
        // 提取置信度标记
        final labelMatch = RegExp(r'^\[(.*?)\]').firstMatch(normalizedEntry);
        bestLabel = labelMatch?.group(1) ?? '';
      }
    }

    if (maxSim > 0.9) {
      return MergeResult(
        action: 'skip',
        message: '记忆已存在（相似度 ${(maxSim * 100).round()}%），跳过写入。',
      );
    }

    if (maxSim >= 0.5) {
      // 替换旧条目：保留原置信度标签，内容更新为新内容，并加 (已更新) 后缀。
      final updated = existingCoreMemory.replaceFirst(
        bestMatch,
        '- [$bestLabel] $newEntry (已更新)',
      );
      return MergeResult(
        action: 'replace',
        mergedCoreMemory: updated,
        message: '已更新已有记忆（相似度 ${(maxSim * 100).round()}%）。',
      );
    }

    // 检查是否与[确信]条目矛盾（简化：反向相似度检查）
    if (bestLabel == '确信') {
      // 使用简单启发式：如果新条目包含与确信条目相反的模式
      final contradiction = _checkContradiction(newEntry, bestMatch);
      if (contradiction) {
        return MergeResult(
          action: 'conflict',
          message: '已写入新记忆，但与已有[确信]条目存在矛盾，已标注[待确认]。',
        );
      }
    }

    return const MergeResult(action: 'append', message: '已写入新记忆。');
  }

  // ---------------------------------------------------------------------------
  // 内部工具
  // ---------------------------------------------------------------------------

  /// 公开访问默认模板，用于重置数据后恢复文件结构。
  String get defaultUserModel => _defaultUserModel();

  String _defaultUserModel() {
    return '''# Sumi 对你的理解

$_systemManagedSection

## 核心记忆
<!-- HOT: AI 写入，每次对话注入，保持 ≤ 8 条 -->
<!-- END CORE MEMORY -->

## 领域画像
<!-- WARM: 评估/规划时按项目领域注入 -->
<!-- END DOMAIN -->

## 长期偏好
<!-- WARM: 对话/规划时注入 -->
<!-- END PREFS -->

## 归档
<!-- COLD: 超过 30 天的旧记忆，AI 通过 read_memory 显式查询 -->
<!-- END ARCHIVE -->
''';
  }

  /// 区段标题到 <!-- END ... --> 标记的映射。
  String? _sectionMarker(String section) {
    return switch (section) {
      'coreMemory' => 'END CORE MEMORY',
      'domainProfile' => 'END DOMAIN',
      'longTermPrefs' => 'END PREFS',
      'archive' => 'END ARCHIVE',
      _ => null,
    };
  }

  /// 在指定标记前追加条目。
  String _appendUnderSection(String content, String endMarker, String entry) {
    final idx = content.indexOf('<!-- $endMarker -->');
    if (idx == -1) return content;
    return '${content.substring(0, idx)}- $entry\n${content.substring(idx)}';
  }

  /// 提取指定区段的内容。
  String _extractSection(String content, String sectionTitle) {
    final start = content.indexOf('## $sectionTitle');
    if (start == -1) return '';
    final nextSection = RegExp(
      r'\n## \S',
    ).firstMatch(content.substring(start + 3));
    if (nextSection != null) {
      return content.substring(start, start + 3 + nextSection.start).trim();
    }
    return content.substring(start).trim();
  }

  /// 限制核心记忆条目数（保留最近 N 条）。
  String _trimCoreMemory(String coreSection, int maxEntries) {
    final lines = coreSection.split('\n');
    final entries = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('- ') || trimmed.startsWith('-[')) {
        entries.add(line);
      }
    }
    if (entries.length <= maxEntries) return coreSection;
    return entries.take(maxEntries).join('\n');
  }

  /// 解析核心记忆中的条目列表。
  List<String> _parseCoreEntries(String coreSection) {
    final entries = <String>[];
    for (final line in coreSection.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('- ') || trimmed.startsWith('-[')) {
        entries.add(trimmed);
      }
    }
    return entries;
  }

  /// Dice coefficient（2-gram 重叠 / 总 n-gram 数）。
  double _diceCoefficient(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    final aGrams = _bigrams(a);
    final bGrams = _bigrams(b);
    final intersect = aGrams.where((g) => bGrams.contains(g)).length;
    return (2.0 * intersect) / (aGrams.length + bGrams.length);
  }

  Set<String> _bigrams(String s) {
    final grams = <String>{};
    for (var i = 0; i < s.length - 1; i++) {
      grams.add(s.substring(i, i + 2));
    }
    return grams;
  }

  /// 简化矛盾检测：负面词表匹配。
  bool _checkContradiction(String newEntry, String existing) {
    final negativeIndicators = ['不', '讨厌', '别', '不要', '不喜欢', '拒绝'];
    final positiveIndicators = ['喜欢', '偏好', '习惯', '适合', '高效'];

    final newHasNegative = negativeIndicators.any((w) => newEntry.contains(w));
    final existingHasPositive = positiveIndicators.any(
      (w) => existing.contains(w),
    );
    final newHasPositive = positiveIndicators.any((w) => newEntry.contains(w));
    final existingHasNegative = negativeIndicators.any(
      (w) => existing.contains(w),
    );

    return (newHasNegative && existingHasPositive) ||
        (newHasPositive && existingHasNegative);
  }

  /// 将超出限额的条目从核心记忆移到归档区。
  String _moveExcessToArchive(String content, int keepCount) {
    final coreStart = content.indexOf('## 核心记忆');
    final coreEnd = content.indexOf('<!-- END CORE MEMORY -->');
    if (coreStart == -1 || coreEnd == -1) return content;

    final coreSection = content.substring(coreStart, coreEnd);
    final entries = _parseCoreEntries(coreSection);
    if (entries.length <= keepCount) return content;

    final toArchive = entries.sublist(keepCount);
    final kept = entries.sublist(0, keepCount);

    // 重建核心记忆区
    final newCore = '## 核心记忆\n${kept.join('\n')}\n';

    // 追加到归档区
    final archiveStart = content.indexOf('## 归档');
    if (archiveStart != -1) {
      final archiveEnd = content.indexOf('<!-- END ARCHIVE -->', archiveStart);
      final archiveEntries = toArchive.join('\n');
      return '${content.substring(0, coreStart)}$newCore'
          '${content.substring(coreEnd + '<!-- END CORE MEMORY -->'.length, archiveEnd)}'
          '\n$archiveEntries\n'
          '${content.substring(archiveEnd)}';
    }

    return content;
  }
}
