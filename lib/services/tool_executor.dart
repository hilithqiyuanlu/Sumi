import 'ai_service.dart';
import 'model_router.dart';
import '../data/signal_database.dart';
import '../models/models.dart';
import '../services/memory_service.dart';

/// 工具执行器 —— 回答 Agent 只能读取结构化记忆。
class ToolExecutor {
  final WebSearchCapability? searchService;
  final MemoryService memoryService;
  final SignalDatabase signalDatabase;
  final String Function() currentUserMessage;
  final String? Function() currentConversationId;
  final bool Function(String name) isToolEnabled;
  final String Function() defaultTodoDate;
  final String Function({String? filter}) readTodos;
  final Future<void> Function({
    required String title,
    String? date,
    String? projectId,
    String? body,
  })
  writeTodo;
  final Future<void> Function({
    required String todoId,
    String? date,
  })
  moveTodoDate;
  final Future<void> Function({
    required String todoId,
    String? title,
    String? body,
  })
  editTodo;
  final Future<void> Function({required String todoId}) deleteTodo;
  final Future<void> Function({
    required String todoId,
    required bool completed,
  })
  toggleTodoCompletion;
  final Future<String> Function({
    required String toolCallId,
    required String conversationId,
    required String title,
    required String kind,
    int? minutes,
    String? alertAt,
    required bool startImmediately,
  })
  createStudyTimer;
  final Future<String> Function({
    required String toolCallId,
    required String conversationId,
    required String goal,
    required String level,
    required int cycleMonths,
    required int timeConstraint,
  })
  startProjectGeneration;

  ToolExecutor({
    this.searchService,
    required this.memoryService,
    required this.signalDatabase,
    required this.currentUserMessage,
    required this.currentConversationId,
    required this.isToolEnabled,
    required this.defaultTodoDate,
    required this.readTodos,
    required this.writeTodo,
    required this.moveTodoDate,
    required this.editTodo,
    required this.deleteTodo,
    required this.toggleTodoCompletion,
    required this.createStudyTimer,
    required this.startProjectGeneration,
  });

  /// 执行单个 tool call，返回字符串结果（作为 tool role 消息的 content）。
  Future<String> execute(ToolCall call) async {
    if (!isToolEnabled(call.name)) return '工具已关闭，无法执行。';
    switch (call.name) {
      case 'search_web':
        return _searchWeb(call.arguments);
      case 'read_memory':
        return _readMemory(call.arguments);
      case 'read_todos':
        return _readTodos(call.arguments);
      case 'write_todo':
        return await _writeTodo(call.arguments);
      case 'move_todo_date':
        return await _moveTodoDate(call.arguments);
      case 'edit_todo':
        return await _editTodo(call.arguments);
      case 'delete_todo':
        return await _deleteTodo(call.arguments);
      case 'toggle_todo_completion':
        return await _toggleTodoCompletion(call.arguments);
      case 'read_signals':
        return await _readSignals(call.arguments);
      case 'create_study_timer':
        return _createStudyTimer(call);
      case 'start_project_generation':
        return _startProjectGeneration(call);
      default:
        return '未知工具：${call.name}';
    }
  }

  Future<String> _startProjectGeneration(ToolCall call) async {
    final conversationId = currentConversationId();
    if (conversationId == null || conversationId.isEmpty) {
      return '启动项目生成失败：当前对话不可用。';
    }
    try {
      return await startProjectGeneration(
        toolCallId: call.id,
        conversationId: conversationId,
        goal: call.arguments['goal'] as String,
        level: call.arguments['level'] as String,
        cycleMonths: call.arguments['cycleMonths'] as int,
        timeConstraint: call.arguments['timeConstraint'] as int,
      );
    } catch (error) {
      return '启动项目生成失败：$error';
    }
  }

  Future<String> _createStudyTimer(ToolCall call) async {
    final conversationId = currentConversationId();
    if (conversationId == null || conversationId.isEmpty) {
      return '创建学习计时器失败：当前对话不可用。';
    }
    try {
      return await createStudyTimer(
        toolCallId: call.id,
        conversationId: conversationId,
        title: (call.arguments['title'] as String?)?.trim() ?? '',
        kind: call.arguments['kind'] as String? ?? 'timer',
        minutes: call.arguments['minutes'] as int?,
        alertAt: call.arguments['alertAt'] as String?,
        startImmediately: call.arguments['startImmediately'] as bool? ?? false,
      );
    } catch (error) {
      return '创建学习计时器失败：$error';
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
        '${i + 1}. ${r['title']}\n   ${r['content']}\n   链接：${r['url']}',
      );
    }
    return buf.toString();
  }

  Future<String> _readMemory(Map<String, Object?> args) async {
    try {
      return await memoryService.formatForAgent(
        (args['query'] as String?)?.trim() ?? currentUserMessage(),
      );
    } catch (e) {
      return '读取记忆失败：$e';
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
        date: args['date'] as String? ?? defaultTodoDate(),
        projectId: args['projectId'] as String?,
        body: args['body'] as String?,
      );
      return '已创建事项：$title';
    } catch (e) {
      return '创建事项失败：$e';
    }
  }

  Future<String> _moveTodoDate(Map<String, Object?> args) async {
    final todoId = (args['todoId'] as String?)?.trim();
    if (todoId == null || todoId.isEmpty) {
      return '错误：未提供待办 id';
    }
    final date = args['date'] as String?;
    try {
      await moveTodoDate(
        todoId: todoId,
        date: date == null || date.isEmpty ? null : date,
      );
      return date == null || date.isEmpty
          ? '已将该事项从日期中移除。'
          : '已将该事项移动到 $date。';
    } catch (e) {
      return '移动事项失败：$e';
    }
  }

  Future<String> _editTodo(Map<String, Object?> args) async {
    final todoId = (args['todoId'] as String?)?.trim();
    if (todoId == null || todoId.isEmpty) {
      return '错误：未提供待办 id';
    }
    final title = (args['title'] as String?)?.trim();
    final body = (args['body'] as String?)?.trim();
    if ((title == null || title.isEmpty) &&
        (body == null || body.isEmpty)) {
      return '错误：未提供要修改的标题或备注';
    }
    try {
      await editTodo(
        todoId: todoId,
        title: title == null || title.isEmpty ? null : title,
        body: body == null || body.isEmpty ? null : body,
      );
      return '已更新事项内容。';
    } catch (e) {
      return '编辑事项失败：$e';
    }
  }

  Future<String> _deleteTodo(Map<String, Object?> args) async {
    final todoId = (args['todoId'] as String?)?.trim();
    if (todoId == null || todoId.isEmpty) {
      return '错误：未提供待办 id';
    }
    final confirmed = args['confirmed'] as bool? ?? false;
    if (!confirmed) {
      return '即将删除该待办，请向用户确认是否继续；确认后请再次调用并传入 confirmed=true。';
    }
    try {
      await deleteTodo(todoId: todoId);
      return '已删除该事项。';
    } catch (e) {
      return '删除事项失败：$e';
    }
  }

  Future<String> _toggleTodoCompletion(Map<String, Object?> args) async {
    final todoId = (args['todoId'] as String?)?.trim();
    if (todoId == null || todoId.isEmpty) {
      return '错误：未提供待办 id';
    }
    final completed = args['completed'] as bool?;
    if (completed == null) {
      return '错误：未提供目标完成状态';
    }
    final confirmed = args['confirmed'] as bool? ?? false;
    if (!confirmed) {
      return '即将把该待办标记为${completed ? '已完成' : '未完成'}，请向用户确认是否继续；确认后请再次调用并传入 confirmed=true。';
    }
    try {
      await toggleTodoCompletion(
        todoId: todoId,
        completed: completed,
      );
      return '已将该事项标记为${completed ? '已完成' : '未完成'}。';
    } catch (e) {
      return '标记完成状态失败：$e';
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
}
