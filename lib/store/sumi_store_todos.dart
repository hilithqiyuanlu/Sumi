part of 'sumi_store.dart';

// ---------------------------------------------------------------------------
// Todo Mutations mixin（07 轮：增加信号采集 + 过去日期门禁 + 编辑区分）
// ---------------------------------------------------------------------------

mixin SumiStoreTodos {
  List<TodoItem> get todoItems;
  List<Project> get projectList;
  DateTime get selectedDate;
  DateTime get currentTime;
  StructuredGenerationCapability? get structuredAi;
  SignalService? get signalService; // 07 轮
  Future<void> onProjectTodoCompleted(TodoItem todo);
  Future<void> onProjectTodoDeleted(TodoItem todo);
  void afterTodoMutation({bool affectsTodayLoad = false});

  bool _affectsTodayLoad(String? before, [String? after]) {
    final today = dateKey(currentTime);
    return before == today || after == today;
  }

  // ---------------------------------------------------------------------------
  // 创建
  // ---------------------------------------------------------------------------

  /// 添加用户 todo —— 自动赋值 date（当前选中日期）和 sortOrder。
  Future<TodoItem?> addUserTodo(
    String title, {
    String? condensedFrom,
    String? date,
    String? body,
    String? reminderTime,
  }) async {
    if (title.trim().isEmpty) return null;
    final nextOrder = _nextSortOrder();
    final todo = TodoItem(
      id: newSumiId('todo'),
      source: TodoSource.user,
      date: date ?? dateKey(selectedDate),
      title: title.trim(),
      body: body,
      reminderTime: reminderTime,
      sortOrder: nextOrder,
      createdAt: DateTime.now(),
      condensedFrom: condensedFrom,
    );
    todoItems.add(todo);
    afterTodoMutation(affectsTodayLoad: _affectsTodayLoad(todo.date));
    await signalService?.emitTodoCreated(todo);
    return todo;
  }

  /// 将一组已确认标题一次写入同一天，只触发一次领域通知。
  Future<List<TodoItem>> addUserTodosForDate(
    List<String> titles, {
    required String date,
    String? condensedFrom,
  }) async {
    final normalized = titles
        .map((title) => title.trim())
        .where((title) => title.isNotEmpty)
        .toList(growable: false);
    if (normalized.isEmpty) return const [];
    var nextOrder = _nextSortOrder();
    final created = <TodoItem>[
      for (final title in normalized)
        TodoItem(
          id: newSumiId('todo'),
          source: TodoSource.user,
          date: date,
          title: title,
          sortOrder: nextOrder++,
          createdAt: DateTime.now(),
          condensedFrom: condensedFrom,
        ),
    ];
    todoItems.addAll(created);
    afterTodoMutation(affectsTodayLoad: _affectsTodayLoad(date));
    for (final todo in created) {
      await signalService?.emitTodoCreated(todo);
    }
    return List.unmodifiable(created);
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
    afterTodoMutation(affectsTodayLoad: _affectsTodayLoad(todo.date));
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
    final isCompleting = !todo.done;
    todoItems[i] = todo.copyWith(
      done: isCompleting,
      completedAt: isCompleting ? DateTime.now() : null,
    );
    afterTodoMutation(affectsTodayLoad: _affectsTodayLoad(todo.date));
    if (todoItems[i].done) {
      await signalService?.emitTodoCompleted(todoItems[i]);
      await onProjectTodoCompleted(todoItems[i]);
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
    await onProjectTodoDeleted(todo);
    todoItems.removeWhere((t) => t.id == id);
    afterTodoMutation(affectsTodayLoad: _affectsTodayLoad(todo.date));
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
    afterTodoMutation(affectsTodayLoad: _affectsTodayLoad(oldDate, date));
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
          afterTodoMutation(affectsTodayLoad: _affectsTodayLoad(todo.date));
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
            completedAt: todo.completedAt,
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
    afterTodoMutation(
      affectsTodayLoad:
          title != null &&
          title.trim() != todo.title &&
          _affectsTodayLoad(todo.date),
    );
  }
}
