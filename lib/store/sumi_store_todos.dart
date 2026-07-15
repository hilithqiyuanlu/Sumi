part of 'sumi_store.dart';

// ---------------------------------------------------------------------------
// Todo Mutations mixin（07 轮：增加信号采集 + 过去日期门禁 + 编辑区分）
// ---------------------------------------------------------------------------

mixin SumiStoreTodos {
  List<TodoItem> get todoItems;
  List<Project> get projectList;
  DateTime get selectedDate;
  StructuredGenerationCapability? get structuredAi;
  SignalService? get signalService; // 07 轮
  void afterTodoMutation();

  // ---------------------------------------------------------------------------
  // 创建
  // ---------------------------------------------------------------------------

  /// 添加用户 todo —— 自动赋值 date（当前选中日期）和 sortOrder。
  Future<TodoItem?> addUserTodo(
    String title, {
    String? condensedFrom,
    String? date,
    String? body,
  }) async {
    if (title.trim().isEmpty) return null;
    final nextOrder = _nextSortOrder();
    final todo = TodoItem(
      id: newSumiId('todo'),
      source: TodoSource.user,
      date: date ?? dateKey(selectedDate),
      title: title.trim(),
      body: body,
      sortOrder: nextOrder,
      createdAt: DateTime.now(),
      condensedFrom: condensedFrom,
    );
    todoItems.add(todo);
    afterTodoMutation();
    await signalService?.emitTodoCreated(todo);
    return todo;
  }

  /// 添加系统 todo。
  Future<TodoItem?> addSystemTodo(
    String title,
    String projectId, {
    String? date,
    String? body,
  }) async {
    if (title.trim().isEmpty) return null;
    final nextOrder = _nextSortOrder();
    final todo = TodoItem(
      id: newSumiId('todo'),
      source: TodoSource.system,
      projectId: projectId,
      date: date,
      title: title.trim(),
      body: body,
      sortOrder: nextOrder,
      createdAt: DateTime.now(),
    );
    todoItems.add(todo);
    afterTodoMutation();
    await signalService?.emitTodoCreated(todo);
    return todo;
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
  Future<void> toggleTodo(String id) async {
    final i = todoItems.indexWhere((t) => t.id == id);
    if (i == -1) return;
    final todo = todoItems[i];
    if (isPastDate(todo.date)) return; // 07 轮：过去日期不可操作
    todoItems[i] = todo.copyWith(done: !todo.done);
    afterTodoMutation();
    if (todoItems[i].done) {
      await signalService?.emitTodoCompleted(todoItems[i]);
    } else {
      await signalService?.emitTodoUncompleted(todoItems[i]);
    }
  }

  /// 删除 todo。
  Future<void> deleteTodo(String id) async {
    final i = todoItems.indexWhere((t) => t.id == id);
    if (i == -1) return;
    final todo = todoItems[i];
    if (isPastDate(todo.date)) return; // 07 轮：过去日期不可删除
    await signalService?.emitTodoDeleted(todo);
    todoItems.removeWhere((t) => t.id == id);
    afterTodoMutation();
  }

  /// 更新标题（含编辑区分 + 凝练还原保护）。
  Future<void> updateTodoTitle(String id, String newTitle) async {
    if (newTitle.trim().isEmpty) {
      deleteTodo(id); // 清空标题 ≈ 删除
      return;
    }
    final i = todoItems.indexWhere((t) => t.id == id);
    if (i == -1) return;
    final todo = todoItems[i];
    if (isPastDate(todo.date)) return; // 07 轮：过去日期不可编辑

    final classification =
        signalService?.classifyEdit(
          todo.title,
          newTitle.trim(),
          condensedFrom: todo.condensedFrom,
        ) ??
        EditClassification.minor;

    switch (classification) {
      case EditClassification.condensedRestore:
        // 还原为凝练前文本 → 不产生信号，直接更新
        todoItems[i] = todo.copyWith(title: newTitle.trim());
      case EditClassification.cleared:
        await signalService?.emitTodoDeleted(todo);
        todoItems.removeWhere((t) => t.id == id);
      case EditClassification.major:
        await signalService?.emitTodoDeleted(todo, reason: 'largeEdit');
        final newTodo = TodoItem(
          id: id,
          source: todo.source,
          projectId: todo.projectId,
          date: todo.date,
          title: newTitle.trim(),
          body: todo.body,
          done: todo.done,
          pinned: todo.pinned,
          sortOrder: todo.sortOrder,
          reminderTime: todo.reminderTime,
          createdAt: todo.createdAt,
        );
        todoItems[i] = newTodo;
        await signalService?.emitTodoCreated(newTodo);
      case EditClassification.minor:
        await signalService?.emitTodoEdited(todo, todo.title, newTitle.trim());
        todoItems[i] = todo.copyWith(title: newTitle.trim());
    }
    afterTodoMutation();
  }

  // ---------------------------------------------------------------------------
  // Pin
  // ---------------------------------------------------------------------------

  /// 切换置顶。
  void togglePin(String id) {
    final i = todoItems.indexWhere((t) => t.id == id);
    if (i == -1) return;
    if (isPastDate(todoItems[i].date)) return; // 07 轮：过去日期不可操作
    todoItems[i] = todoItems[i].copyWith(pinned: !todoItems[i].pinned);
    afterTodoMutation();
    // 置顶不产生信号
  }

  // ---------------------------------------------------------------------------
  // 日期
  // ---------------------------------------------------------------------------

  /// 更新 todo 的分配日期。传 null 表示清空日期。
  Future<void> updateTodoDate(String id, String? date) async {
    final i = todoItems.indexWhere((t) => t.id == id);
    if (i == -1) return;
    final todo = todoItems[i];
    if (isPastDate(todo.date)) return; // 07 轮：过去日期不可拖拽
    final oldDate = todo.date ?? '';
    todoItems[i] = todo.copyWith(date: date);
    afterTodoMutation();
    await signalService?.emitTodoMovedDate(todoItems[i], oldDate, date ?? '');
  }

  // ---------------------------------------------------------------------------
  // 项目归属
  // ---------------------------------------------------------------------------

  /// 更新 todo 的项目归属。传 null 表示移除项目归属。
  Future<void> updateTodoProject(String id, String? projectId) async {
    final i = todoItems.indexWhere((t) => t.id == id);
    if (i == -1) return;
    final todo = todoItems[i];
    if (isPastDate(todo.date)) return; // 07 轮：过去日期不可操作
    await signalService?.emitTodoEdited(
      todo,
      todo.title,
      todo.title,
      projectChanged: true,
    );
    todoItems[i] = todo.copyWith(projectId: projectId);
    afterTodoMutation();
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
    todoItems[targetIdx] = todoItems[targetIdx].copyWith(sortOrder: dragOrder);
    afterTodoMutation();
    // 排序不产生信号
  }

  // ---------------------------------------------------------------------------
  // AI 润色
  // ---------------------------------------------------------------------------

  /// 调用 AI 凝练任意文本至 18 字以内。失败返回 null。
  Future<String?> polishText(String text) async {
    final svc = structuredAi;
    if (svc == null) return null;
    return await svc.polishTodo(text);
  }

  // ---------------------------------------------------------------------------
  // 批量更新（编辑面板用）
  // ---------------------------------------------------------------------------

  /// 批量更新 todo 字段（07 轮：增加编辑区分）。
  /// [body]/[projectId]/[reminderTime] 传 null 表示不修改；如需清空请使用
  /// [updateTodoProject]、[updateTodoDate] 或传 [TodoItem.undefined] 哨兵。
  Future<void> updateTodo(
    String id, {
    String? title,
    String? body,
    String? projectId,
    String? reminderTime,
  }) async {
    final i = todoItems.indexWhere((t) => t.id == id);
    if (i == -1) return;
    final todo = todoItems[i];
    if (isPastDate(todo.date)) return; // 07 轮：过去日期不可编辑

    // 将 null 解释为“不修改”，转换为哨兵值传入 copyWith。
    final bodyArg = body ?? TodoItem.undefined;
    final projectIdArg = projectId ?? TodoItem.undefined;
    final reminderTimeArg = reminderTime ?? TodoItem.undefined;

    // 标题变更使用编辑区分
    if (title != null && title.trim() != todo.title) {
      final classification =
          signalService?.classifyEdit(
            todo.title,
            title.trim(),
            condensedFrom: todo.condensedFrom,
          ) ??
          EditClassification.minor;

      switch (classification) {
        case EditClassification.condensedRestore:
          todoItems[i] = todo.copyWith(
            title: title.trim(),
            body: bodyArg,
            projectId: projectIdArg,
            reminderTime: reminderTimeArg,
          );
        case EditClassification.cleared:
          await signalService?.emitTodoDeleted(todo);
          todoItems.removeWhere((t) => t.id == id);
          afterTodoMutation();
          return;
        case EditClassification.major:
          await signalService?.emitTodoDeleted(todo, reason: 'largeEdit');
          final newTodo = TodoItem(
            id: id,
            source: todo.source,
            projectId: todo.projectId,
            date: todo.date,
            title: title.trim(),
            body: body ?? todo.body,
            done: todo.done,
            pinned: todo.pinned,
            sortOrder: todo.sortOrder,
            reminderTime: reminderTime ?? todo.reminderTime,
            createdAt: todo.createdAt,
          );
          todoItems[i] = newTodo;
          await signalService?.emitTodoCreated(newTodo);
        case EditClassification.minor:
          await signalService?.emitTodoEdited(todo, todo.title, title.trim());
          todoItems[i] = todo.copyWith(
            title: title.trim(),
            body: bodyArg,
            projectId: projectIdArg,
            reminderTime: reminderTimeArg,
          );
      }
    } else {
      // 仅 body/projectId/reminderTime 变更，不产生信号
      todoItems[i] = todo.copyWith(
        body: bodyArg,
        projectId: projectIdArg,
        reminderTime: reminderTimeArg,
      );
    }
    afterTodoMutation();
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

  /// 排序后的 todo 列表。
  List<TodoItem> get sortedTodos {
    final list = List<TodoItem>.of(todoItems);
    list.sort(_todoComparator);
    return list;
  }

  int _todoComparator(TodoItem a, TodoItem b) {
    if (a.pinned && !b.pinned) return -1;
    if (!a.pinned && b.pinned) return 1;
    if (!a.done && b.done) return -1;
    if (a.done && !b.done) return 1;
    return a.sortOrder.compareTo(b.sortOrder);
  }
}
