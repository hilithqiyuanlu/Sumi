import 'ai_service.dart';
import 'ai_runtime.dart';
import '../data/signal_database.dart';
import '../models/models.dart';
import '../services/user_model_service.dart';

/// 工具执行器 —— 执行 AI 返回的 tool_calls，返回文本结果。
/// 07 轮改造：新增 read_signals、write_memory 合并逻辑、USER_MODEL.md 读写。
class ToolExecutor {
  final WebSearchService? searchService;
  final UserModelService userModelService;
  final SignalDatabase signalDatabase;
  final String Function({String? filter}) readTodos;
  final Future<void> Function({
    required String title,
    String? date,
    String? projectId,
    String? body,
  }) writeTodo;

  ToolExecutor({
    this.searchService,
    required this.userModelService,
    required this.signalDatabase,
    required this.readTodos,
    required this.writeTodo,
  });

  /// 执行单个 tool call，返回字符串结果（作为 tool role 消息的 content）。
  Future<String> execute(ToolCall call) async {
    switch (call.name) {
      case 'search_web':
        return _searchWeb(call.arguments);
      case 'read_memory':
        return _readMemory();
      case 'write_memory':
        return _writeMemory(call.arguments);
      case 'read_todos':
        return _readTodos(call.arguments);
      case 'write_todo':
        return await _writeTodo(call.arguments);
      case 'read_signals':
        return await _readSignals(call.arguments);
      default:
        return '未知工具：${call.name}';
    }
  }

  Future<String> _searchWeb(Map<String, Object?> args) async {
    final query = (args['query'] as String?)?.trim();
    if (query == null || query.isEmpty) {
      return '错误：未提供搜索关键词';
    }
    if (searchService == null) {
      return '错误：搜索服务未配置';
    }
    final results = await searchService!.search(query);
    if (results.isEmpty) {
      return '未找到相关结果。';
    }
    if (results.first.containsKey('error')) {
      return results.first['error']!;
    }
    if (results.first.containsKey('info')) {
      return results.first['info']!;
    }
    final buf = StringBuffer('搜索「$query」的结果：\n');
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      buf.writeln(
          '${i + 1}. ${r['title']}\n   ${r['content']}\n   链接：${r['url']}');
    }
    return buf.toString();
  }

  Future<String> _readMemory() async {
    try {
      final content = await userModelService.readUserModel();
      if (content.trim().isEmpty) return '（暂无记忆）';

      final stats = await userModelService.computeRealtimeStats();
      final withStats = userModelService.injectRealtimeStats(content, stats);
      final hot = userModelService.buildHotPrompt(withStats);
      final prefs = userModelService.buildWarmPrefsPrompt(withStats);

      final buf = StringBuffer();
      buf.writeln(hot);
      if (prefs.isNotEmpty) {
        buf.writeln();
        buf.writeln(prefs);
      }
      buf.writeln();
      buf.writeln('（提示：使用 read_signals 查询历史行为模式，使用 read_memory 查询全文归档记忆）');
      return buf.toString();
    } catch (e) {
      return '读取记忆失败：$e';
    }
  }

  /// 07 轮：写入记忆含合并逻辑（去重/替换/矛盾标注）。
  Future<String> _writeMemory(Map<String, Object?> args) async {
    final content = (args['content'] as String?)?.trim();
    if (content == null || content.isEmpty) {
      return '错误：未提供要写入的记忆内容';
    }

    // 获取置信度标记（AI 可选提供）
    final confidence = (args['confidence'] as String?) == '确信' ? '确信' : '推断';

    try {
      // 读取当前 USER_MODEL.md
      final currentModel = await userModelService.readUserModel();
      final sections = _parseSections(currentModel);
      final coreMemory = sections['coreMemory'] ?? '';

      // 执行合并判断
      final mergeResult = userModelService.mergeMemoryEntry(content, coreMemory);

      switch (mergeResult.action) {
        case 'skip':
          return mergeResult.message;
        case 'replace':
          // 替换核心记忆区
          final updated = _replaceCoreMemorySection(currentModel, mergeResult.mergedCoreMemory!);
          await userModelService.writeUserModel(updated);
          return mergeResult.message;
        case 'append':
          // 内容由 _appendUnderSection 统一添加 '- ' 前缀，这里不再加。
          final entry = '[$confidence] $content';
          await userModelService.appendToSection('coreMemory', entry);
          return mergeResult.message;
        case 'conflict':
          final entry = '[待确认] $content（与已有[确信]条目矛盾）';
          await userModelService.appendToSection('coreMemory', entry);
          return mergeResult.message;
        default:
          return '写入记忆失败：未知合并动作 ${mergeResult.action}';
      }
    } catch (e) {
      return '写入记忆失败：$e';
    }
  }

  String _readTodos(Map<String, Object?> args) {
    final filter = args['filter'] as String?;
    try {
      final result = readTodos(filter: filter);
      if (result.isEmpty) {
        return '未找到匹配的待办事项。';
      }
      return result;
    } catch (e) {
      return '查询待办事项失败：$e';
    }
  }

  Future<String> _writeTodo(Map<String, Object?> args) async {
    final title = (args['title'] as String?)?.trim();
    if (title == null || title.isEmpty) {
      return '错误：未提供事项标题';
    }
    try {
      await writeTodo(
        title: title,
        date: args['date'] as String?,
        projectId: args['projectId'] as String?,
        body: args['body'] as String?,
      );
      return '已创建事项：$title';
    } catch (e) {
      return '创建事项失败：$e';
    }
  }

  /// 07 轮新增：查询用户历史行为信号。
  Future<String> _readSignals(Map<String, Object?> args) async {
    final typeStr = args['type'] as String?;
    final projectId = args['projectId'] as String?;
    final range = (args['range'] as String?) ?? '7d';
    final limit = (args['limit'] as int?) ?? 20;

    // 解析类型筛选
    SignalType? typeFilter;
    if (typeStr != null && typeStr.isNotEmpty) {
      typeFilter = SignalType.values.firstWhere(
        (t) => t.name == typeStr,
        orElse: () {
          // 尝试作为逗号分隔列表的第一项
          final first = typeStr.split(',').first.trim();
          return SignalType.values.firstWhere(
            (t) => t.name == first,
            orElse: () => SignalType.todoCreated,
          );
        },
      );
    }

    try {
      final signals = await signalDatabase.query(
        type: typeFilter,
        projectId: projectId,
        range: range,
        limit: limit,
      );

      if (signals.isEmpty) {
        return '（暂无符合条件的信号）';
      }

      return SignalDatabase.formatForPrompt(signals);
    } catch (e) {
      return '查询信号失败：$e';
    }
  }

  // ---------------------------------------------------------------------------
  // 内部
  // ---------------------------------------------------------------------------

  /// 简单解析 USER_MODEL.md 的主要区段。
  /// 返回英文键，与 [_writeMemory] 中 `sections['coreMemory']` 等用法对齐。
  Map<String, String> _parseSections(String content) {
    final sections = <String, String>{};
    final titles = {
      'coreMemory': '核心记忆',
      'domainProfile': '领域画像',
      'longTermPrefs': '长期偏好',
      'archive': '归档',
    };
    for (final entry in titles.entries) {
      final key = entry.key;
      final title = entry.value;
      final start = content.indexOf('## $title');
      if (start == -1) continue;
      final nextSection = RegExp(r'\n## \S').firstMatch(content.substring(start + 3));
      if (nextSection != null) {
        sections[key] = content.substring(start, start + 3 + nextSection.start);
      } else {
        sections[key] = content.substring(start);
      }
    }
    return sections;
  }

  /// 替换 USER_MODEL.md 中的核心记忆区。
  String _replaceCoreMemorySection(String fullContent, String newCoreMemory) {
    final start = fullContent.indexOf('## 核心记忆');
    if (start == -1) return fullContent;
    final end = fullContent.indexOf('##', start + 3);
    if (end == -1) {
      return '${fullContent.substring(0, start)}$newCoreMemory';
    }
    return '${fullContent.substring(0, start)}$newCoreMemory\n\n${fullContent.substring(end)}';
  }
}
