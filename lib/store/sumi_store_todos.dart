part of 'sumi_store.dart';

// ---------------------------------------------------------------------------
// Todo Mutations mixin
// ---------------------------------------------------------------------------

mixin SumiStoreTodos on ChangeNotifier {
  List<TodoItem> get todoItems;
  void afterMutation();

  /// 添加用户 todo。
  void addUserTodo(String title) {
    if (title.trim().isEmpty) return;
    todoItems.add(TodoItem(
      id: newSumiId('todo'),
      source: TodoSource.user,
      title: title.trim(),
      createdAt: DateTime.now(),
    ));
    afterMutation();
  }

  /// 添加系统 todo。
  void addSystemTodo(String title, String projectId) {
    if (title.trim().isEmpty) return;
    todoItems.add(TodoItem(
      id: newSumiId('todo'),
      source: TodoSource.system,
      projectId: projectId,
      title: title.trim(),
      createdAt: DateTime.now(),
    ));
    afterMutation();
  }

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

  // ——— 便捷查询 ———

  List<TodoItem> get todos => List.unmodifiable(todoItems);

  List<TodoItem> get userTodos =>
      todoItems.where((t) => t.source == TodoSource.user).toList();

  List<TodoItem> get systemTodos =>
      todoItems.where((t) => t.source == TodoSource.system).toList();
}
