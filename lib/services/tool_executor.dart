import 'dart:convert';

import 'ai_service.dart';

/// 工具执行器 —— 执行 AI 返回的 tool_calls，返回文本结果。
class ToolExecutor {
  final AiService? aiService;
  final Future<String> Function() readMemory;
  final Future<void> Function(String content) appendMemory;
  final String Function({String? filter}) readTodos;
  final Future<void> Function({
    required String title,
    String? date,
    String? projectId,
    String? body,
  }) writeTodo;

  ToolExecutor({
    this.aiService,
    required this.readMemory,
    required this.appendMemory,
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
      default:
        return '未知工具：${call.name}';
    }
  }

  Future<String> _searchWeb(Map<String, Object?> args) async {
    final query = (args['query'] as String?)?.trim();
    if (query == null || query.isEmpty) {
      return '错误：未提供搜索关键词';
    }
    if (aiService == null) {
      return '错误：搜索服务未配置';
    }
    final results = await aiService!.searchWeb(query);
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
      final content = await readMemory();
      if (content.trim().isEmpty) {
        return 'MEMORY.md 为空，暂无记忆。';
      }
      // 截断以防超出上下文
      if (content.length > 3000) {
        return '${content.substring(0, 3000)}\n\n（记忆较长，已截断至最近部分）';
      }
      return content;
    } catch (e) {
      return '读取记忆失败：$e';
    }
  }

  Future<String> _writeMemory(Map<String, Object?> args) async {
    final content = (args['content'] as String?)?.trim();
    if (content == null || content.isEmpty) {
      return '错误：未提供要写入的记忆内容';
    }
    try {
      await appendMemory(content);
      return '已写入记忆。';
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
}
