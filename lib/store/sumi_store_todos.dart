part of 'sumi_store.dart';

// ---------------------------------------------------------------------------
// Todo Mutations mixin
// ---------------------------------------------------------------------------

mixin SumiStoreTodos on ChangeNotifier {
  List<TodoItem> get todoItems;
  List<Project> get projectList;
  DateTime get selectedDate;
  AiService? get aiService;
  void afterMutation();

  // ---------------------------------------------------------------------------
  // 创建
  // ---------------------------------------------------------------------------

  /// 添加用户 todo —— 自动赋值 date（当前选中日期）和 sortOrder。
  void addUserTodo(String title) {
    if (title.trim().isEmpty) return;
    final nextOrder = _nextSortOrder();
    todoItems.add(TodoItem(
      id: newSumiId('todo'),
      source: TodoSource.user,
      date: dateKey(selectedDate),
      title: title.trim(),
      sortOrder: nextOrder,
      createdAt: DateTime.now(),
    ));
    afterMutation();
  }

  /// 添加系统 todo。
  void addSystemTodo(String title, String projectId, {String? date, String? body}) {
    if (title.trim().isEmpty) return;
    final nextOrder = _nextSortOrder();
    todoItems.add(TodoItem(
      id: newSumiId('todo'),
      source: TodoSource.system,
      projectId: projectId,
      date: date,
      title: title.trim(),
      body: body,
      sortOrder: nextOrder,
      createdAt: DateTime.now(),
    ));
    afterMutation();
  }

  int _nextSortOrder() {
    if (todoItems.isEmpty) return 0;
    int max = 0;
    for (final t in todoItems) {
      if (t.sortOrder > max) max = t.sortOrder;
    }
    return max + 1;
  }

  // ---------------------------------------------------------------------------
  // 基础 mutation
  // ---------------------------------------------------------------------------

  /// 切换完成状态。
  void toggleTodo(String id) {
    final i = todoItems.indexWhere((t) => t.id == id);
    if (i == -1) return;
    todoItems[i] = todoItems[i].copyWith(done: !todoItems[i].done);
    afterMutation();
  }

  /// 删除 todo。
  void deleteTodo(String id) {
    todoItems.removeWhere((t) => t.id == id);
    afterMutation();
  }

  /// 更新标题。
  void updateTodoTitle(String id, String newTitle) {
    if (newTitle.trim().isEmpty) return;
    final i = todoItems.indexWhere((t) => t.id == id);
    if (i == -1) return;
    todoItems[i] = todoItems[i].copyWith(title: newTitle.trim());
    afterMutation();
  }

  // ---------------------------------------------------------------------------
  // Pin
  // ---------------------------------------------------------------------------

  /// 切换置顶。
  void togglePin(String id) {
    final i = todoItems.indexWhere((t) => t.id == id);
    if (i == -1) return;
    todoItems[i] = todoItems[i].copyWith(pinned: !todoItems[i].pinned);
    afterMutation();
  }

  // ---------------------------------------------------------------------------
  // 日期
  // ---------------------------------------------------------------------------

  /// 更新 todo 的分配日期。
  void updateTodoDate(String id, String? date) {
    final i = todoItems.indexWhere((t) => t.id == id);
    if (i == -1) return;
    todoItems[i] = todoItems[i].copyWith(date: date);
    afterMutation();
  }

  // ---------------------------------------------------------------------------
  // 项目归属
  // ---------------------------------------------------------------------------

  /// 更新 todo 的项目归属（null = 移除项目）。
  void updateTodoProject(String id, String? projectId) {
    final i = todoItems.indexWhere((t) => t.id == id);
    if (i == -1) return;
    todoItems[i] = todoItems[i].copyWith(projectId: projectId);
    afterMutation();
  }

  // ---------------------------------------------------------------------------
  // 提醒
  // ---------------------------------------------------------------------------

  /// 设置或清除提醒时间。
  void updateTodoReminder(String id, String? reminderTime) {
    final i = todoItems.indexWhere((t) => t.id == id);
    if (i == -1) return;
    todoItems[i] = todoItems[i].copyWith(reminderTime: reminderTime);
    afterMutation();
  }

  // ---------------------------------------------------------------------------
  // 拖拽排序
  // ---------------------------------------------------------------------------

  /// 交换两个 todo 的 sortOrder。
  void reorderTodos(String draggedId, String targetId) {
    final dragIdx = todoItems.indexWhere((t) => t.id == draggedId);
    final targetIdx = todoItems.indexWhere((t) => t.id == targetId);
    if (dragIdx == -1 || targetIdx == -1 || dragIdx == targetIdx) return;

    final dragOrder = todoItems[dragIdx].sortOrder;
    final targetOrder = todoItems[targetIdx].sortOrder;
    todoItems[dragIdx] = todoItems[dragIdx].copyWith(sortOrder: targetOrder);
    todoItems[targetIdx] =
        todoItems[targetIdx].copyWith(sortOrder: dragOrder);
    afterMutation();
  }

  // ---------------------------------------------------------------------------
  // AI 润色
  // ---------------------------------------------------------------------------

  /// 调用 AI 润色标题，返回润色后文本。失败返回 null。
  Future<String?> polishTodoTitle(String id) async {
    final i = todoItems.indexWhere((t) => t.id == id);
    if (i == -1) return null;

    final svc = aiService;
    if (svc == null) return null;

    final polished = await svc.polishTodo(todoItems[i].title);
    return polished;
  }

  /// 调用 AI 凝练任意文本至 18 字以内。失败返回 null。
  Future<String?> polishText(String text) async {
    final svc = aiService;
    if (svc == null) return null;
    return await svc.polishTodo(text);
  }

  // ---------------------------------------------------------------------------
  // 批量更新（编辑面板用）
  // ---------------------------------------------------------------------------

  /// 批量更新 todo 字段。
  void updateTodo(
    String id, {
    String? title,
    String? body,
    String? projectId,
    String? reminderTime,
  }) {
    final i = todoItems.indexWhere((t) => t.id == id);
    if (i == -1) return;
    todoItems[i] = todoItems[i].copyWith(
      title: title,
      body: body,
      projectId: projectId,
      reminderTime: reminderTime,
    );
    afterMutation();
  }

  // ---------------------------------------------------------------------------
  // 查询
  // ---------------------------------------------------------------------------

  List<TodoItem> get todos => List.unmodifiable(todoItems);

  List<TodoItem> get userTodos =>
      todoItems.where((t) => t.source == TodoSource.user).toList();

  List<TodoItem> get systemTodos =>
      todoItems.where((t) => t.source == TodoSource.system).toList();

  /// 当前选中日期的 todo（date == null 始终显示，匹配日期的显示）。
  List<TodoItem> get todosForSelectedDate {
    final key = dateKey(selectedDate);
    return sortedTodos.where((t) => t.date == null || t.date == key).toList();
  }

  /// 排序后的 todo 列表：
  /// 1. pinned（sortOrder 降序）
  /// 2. 未完成（sortOrder 降序）
  /// 3. 已完成（sortOrder 降序）
  List<TodoItem> get sortedTodos {
    final list = List<TodoItem>.of(todoItems);
    list.sort(_todoComparator);
    return list;
  }

  int _todoComparator(TodoItem a, TodoItem b) {
    // pinned 置顶
    if (a.pinned && !b.pinned) return -1;
    if (!a.pinned && b.pinned) return 1;
    // 未完成优先于已完成
    if (!a.done && b.done) return -1;
    if (a.done && !b.done) return 1;
    // sortOrder 升序（越小越靠前 = 添加顺序）
    return a.sortOrder.compareTo(b.sortOrder);
  }
}
