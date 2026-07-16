import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/signal_database.dart';
import '../models/models.dart';
import '../utils/utils.dart';

/// 编辑分类结果。
enum EditClassification { minor, major, condensedRestore, cleared }

/// 信号采集服务 —— 纯规则判断，0 token。
/// 负责编辑区分、凝练还原保护、信号发射（07 轮新增）。
class SignalService {
  final SignalDatabase _signalDb;
  final Project? Function(String projectId)? projectForId;

  SignalService(this._signalDb, {this.projectForId});

  // ---------------------------------------------------------------------------
  // 信号发射
  // ---------------------------------------------------------------------------

  Future<void> emitTodoCreated(TodoItem todo) async {
    debugPrint(
      '[SignalService] emitTodoCreated 被调用: "${todo.title}" date=${todo.date}',
    );
    if (isPastDate(todo.date)) {
      debugPrint('[SignalService] 过去日期，跳过');
      return;
    }
    await _insert(
      UserSignal(
        signal: SignalType.todoCreated,
        time: DateTime.now(),
        contextJson: _ctx(todo: todo),
        projectId: todo.projectId,
        todoId: todo.id,
        domain: _inferDomain(todo),
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> emitTodoCompleted(TodoItem todo) async {
    if (isPastDate(todo.date)) return;
    await _insert(
      UserSignal(
        signal: SignalType.todoCompleted,
        time: DateTime.now(),
        contextJson: _ctx(todo: todo, completedOnTime: true),
        projectId: todo.projectId,
        todoId: todo.id,
        domain: _inferDomain(todo),
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> emitTodoUncompleted(TodoItem todo) async {
    if (isPastDate(todo.date)) return;
    await _insert(
      UserSignal(
        signal: SignalType.todoUncompleted,
        time: DateTime.now(),
        contextJson: _ctx(todo: todo, completedOnTime: false),
        projectId: todo.projectId,
        todoId: todo.id,
        domain: _inferDomain(todo),
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> emitTodoDeleted(TodoItem todo, {String? reason}) async {
    if (isPastDate(todo.date)) return;
    await _insert(
      UserSignal(
        signal: SignalType.todoDeleted,
        time: DateTime.now(),
        contextJson: _ctx(
          todo: todo,
          includeTodoContent: false,
          extra: reason == null ? null : {'reason': reason},
        ),
        projectId: todo.projectId,
        todoId: todo.id,
        domain: _inferDomain(todo),
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> emitTodoEdited(
    TodoItem todo,
    String oldTitle,
    String newTitle, {
    bool projectChanged = false,
  }) async {
    debugPrint(
      '[SignalService] emitTodoEdited: "$oldTitle" → "$newTitle" date=${todo.date}',
    );
    if (isPastDate(todo.date)) {
      debugPrint('[SignalService] 过去日期，跳过');
      return;
    }
    final changePercent = _changePercent(oldTitle, newTitle);
    await _insert(
      UserSignal(
        signal: SignalType.todoEdited,
        time: DateTime.now(),
        contextJson: _ctx(
          todo: todo,
          extra: {
            'oldTitle': oldTitle,
            'newTitle': newTitle,
            'changePercent': changePercent,
            'projectChanged': projectChanged,
          },
        ),
        projectId: todo.projectId,
        todoId: todo.id,
        domain: _inferDomain(todo),
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> emitTodoMovedDate(
    TodoItem todo,
    String oldDate,
    String newDate,
  ) async {
    // 过去日期的 todo 不能拖拽，但允许从今天移回今天（无变化）
    if (oldDate == newDate) return;
    final today = dateKey(dateOnly(DateTime.now()));
    // 仅当目标日期是今天或未来时才产生信号
    if (newDate.compareTo(today) < 0) return;
    await _insert(
      UserSignal(
        signal: SignalType.todoMovedDate,
        time: DateTime.now(),
        contextJson: _ctx(
          todo: todo,
          extra: {'oldDate': oldDate, 'newDate': newDate},
        ),
        projectId: todo.projectId,
        todoId: todo.id,
        domain: _inferDomain(todo),
        createdAt: DateTime.now(),
      ),
    );
  }

  // --- 项目信号 ---

  Future<void> emitProjectGoalSet(Project project, String? oldGoal) async {
    if (oldGoal == project.goal) return;
    final goalExtra = <String, dynamic>{'newGoal': project.goal};
    if (oldGoal != null) goalExtra['oldGoal'] = oldGoal;
    await _insert(
      UserSignal(
        signal: SignalType.projectGoalSet,
        time: DateTime.now(),
        contextJson: _projectCtx(project, extra: goalExtra),
        projectId: project.id,
        domain: project.goal,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> emitProjectLevelSet(Project project, String? oldLevel) async {
    if (oldLevel == project.level) return;
    final levelExtra = <String, dynamic>{'newLevel': project.level};
    if (oldLevel != null) levelExtra['oldLevel'] = oldLevel;
    await _insert(
      UserSignal(
        signal: SignalType.projectLevelSet,
        time: DateTime.now(),
        contextJson: _projectCtx(project, extra: levelExtra),
        projectId: project.id,
        domain: project.goal,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> emitProjectCycleSet(Project project, int? oldCycle) async {
    if (oldCycle == project.cycleMonths) return;
    await _insert(
      UserSignal(
        signal: SignalType.projectCycleSet,
        time: DateTime.now(),
        contextJson: _projectCtx(
          project,
          extra: {'oldCycle': oldCycle ?? 0, 'newCycle': project.cycleMonths},
        ),
        projectId: project.id,
        domain: project.goal,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> emitProjectTimeSet(Project project, int? oldTime) async {
    if (oldTime == project.timeConstraint) return;
    await _insert(
      UserSignal(
        signal: SignalType.projectTimeSet,
        time: DateTime.now(),
        contextJson: _projectCtx(
          project,
          extra: {'oldTime': oldTime ?? 0, 'newTime': project.timeConstraint},
        ),
        projectId: project.id,
        domain: project.goal,
        createdAt: DateTime.now(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 编辑区分逻辑
  // ---------------------------------------------------------------------------

  /// 分类编辑类型。
  /// - condensedRestore: 用户将凝练后文本改回凝练前文本 → 不产生信号
  /// - cleared: 用户清空文本 → todoDeleted
  /// - minor: Levenshtein 距离 < 50% → todoEdited
  /// - major: Levenshtein 距离 ≥ 50% → todoDeleted + todoCreated
  EditClassification classifyEdit(
    String oldText,
    String newText, {
    String? condensedFrom,
  }) {
    final oldTrimmed = oldText.trim();
    final newTrimmed = newText.trim();

    // 清空 → 删除
    if (newTrimmed.isEmpty) return EditClassification.cleared;

    // 凝练还原保护：新文本匹配凝练前文本
    if (condensedFrom != null && newTrimmed == condensedFrom.trim()) {
      return EditClassification.condensedRestore;
    }

    // 计算变化比例
    final dist = _levenshteinDistance(oldTrimmed, newTrimmed);
    final maxLen = max(oldTrimmed.length, newTrimmed.length);
    if (maxLen == 0) return EditClassification.minor;

    final ratio = dist / maxLen;
    return ratio >= 0.5 ? EditClassification.major : EditClassification.minor;
  }

  // ---------------------------------------------------------------------------
  // 内部
  // ---------------------------------------------------------------------------

  Future<void> _insert(UserSignal signal) async {
    try {
      await _signalDb.insert(signal);
      debugPrint('[SignalService] 信号已写入: ${signal.signal.name}');
    } catch (e, stack) {
      debugPrint('[SignalService] 信号写入失败: $e');
      debugPrint('[SignalService] 堆栈: $stack');
    }
  }

  /// 构建 todo 信号的 context JSON。
  String _ctx({
    required TodoItem todo,
    bool? completedOnTime,
    bool includeTodoContent = true,
    Map<String, dynamic>? extra,
  }) {
    final now = DateTime.now();
    final map = <String, dynamic>{
      'hourOfDay': now.hour,
      'source': todo.source.name,
    };
    if (includeTodoContent) {
      map['title'] = todo.title;
      if (todo.body != null && todo.body!.trim().isNotEmpty) {
        map['body'] = todo.body;
      }
    }
    if (todo.projectId != null) {
      map['projectId'] = todo.projectId;
      final project = projectForId?.call(todo.projectId!);
      if (project != null) {
        map['projectName'] = project.name;
        map['projectGoal'] = project.goal;
      }
    }
    if (todo.date != null) map['plannedDate'] = todo.date;
    if (completedOnTime != null) {
      map['completedOnTime'] = completedOnTime;
    }
    if (extra != null) map.addAll(extra);
    return jsonEncode(map);
  }

  /// 构建项目信号的 context JSON。
  String _projectCtx(Project project, {Map<String, dynamic>? extra}) {
    final map = <String, dynamic>{
      'name': project.name,
      'goal': project.goal,
      'level': project.level,
      'cycleMonths': project.cycleMonths,
      'timeConstraint': project.timeConstraint,
      'hourOfDay': DateTime.now().hour,
    };
    if (extra != null) map.addAll(extra);
    return jsonEncode(map);
  }

  String? _inferDomain(TodoItem todo) {
    final projectId = todo.projectId;
    if (projectId == null) return null;
    final project = projectForId?.call(projectId);
    final goal = project?.goal.trim() ?? '';
    return goal.isEmpty ? null : goal;
  }

  /// 计算 Levenshtein 编辑距离。
  static int _levenshteinDistance(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final prevRow = List<int>.generate(b.length + 1, (i) => i);
    final currRow = List<int>.filled(b.length + 1, 0);

    for (var i = 0; i < a.length; i++) {
      currRow[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a[i] == b[j] ? 0 : 1;
        currRow[j + 1] = min(
          min(currRow[j] + 1, prevRow[j + 1] + 1),
          prevRow[j] + cost,
        );
      }
      for (var j = 0; j <= b.length; j++) {
        prevRow[j] = currRow[j];
      }
    }
    return prevRow[b.length];
  }

  /// 计算变化百分比（0-100）。
  static int _changePercent(String oldText, String newText) {
    final dist = _levenshteinDistance(oldText, newText);
    final maxLen = max(oldText.length, newText.length);
    if (maxLen == 0) return 0;
    return (dist * 100.0 / maxLen).round();
  }
}
