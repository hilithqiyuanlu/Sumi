part of 'sumi_store.dart';

// ---------------------------------------------------------------------------
// Project & MonthCard Mutations mixin
// ---------------------------------------------------------------------------

mixin SumiStoreProjects {
  List<Project> get projectList;
  List<MonthCard> get monthCardList;
  List<TodoItem> get todoItems;
  String? get currentProjectId;
  set currentProjectId(String? v);
  StructuredGenerationCapability? get structuredAi;
  SignalService? get signalService; // 07 轮
  SignalDatabase? get signalDb;
  MemoryService? get memoryServiceForStore;
  Future<void> onProjectDeleted(String projectId);
  Future<void> onProjectTodoDeleted(TodoItem todo);
  void afterProjectMutation({
    bool affectsTodayLoad = false,
    bool scheduleRollingPlanning = true,
  });

  /// 更新项目字段。编辑保存后，若影响规划的字段变更则自动重新规划。
  Future<void> updateProject(
    String id, {
    String? name,
    ProjectColor? color,
    String? goal,
    String? level,
    int? cycleMonths,
    int? timeConstraint,
    int? currentMonthIndex,
    String? goalSummary,
  }) async {
    final i = projectList.indexWhere((p) => p.id == id);
    if (i == -1) return;
    final old = projectList[i];
    final oldCycle = old.cycleMonths;
    projectList[i] = projectList[i].copyWith(
      name: name,
      color: color,
      goal: goal,
      level: level,
      cycleMonths: cycleMonths,
      timeConstraint: timeConstraint,
      currentMonthIndex: currentMonthIndex,
      goalSummary: goalSummary,
    );
    // 如果 cycleMonths 变更，调整月卡数量
    if (cycleMonths != null && cycleMonths != oldCycle) {
      if (cycleMonths > oldCycle) {
        for (var m = oldCycle; m < cycleMonths; m++) {
          monthCardList.add(
            MonthCard(
              id: newSumiId('mc'),
              projectId: id,
              monthIndex: m,
              title: '',
            ),
          );
        }
      } else {
        monthCardList.removeWhere(
          (mc) => mc.projectId == id && mc.monthIndex >= cycleMonths,
        );
      }
    }

    // 07 轮：采集项目编辑信号
    final updated = projectList[i];
    if (goal != null && goal != old.goal) {
      await signalService?.emitProjectGoalSet(updated, old.goal);
    }
    if (level != null && level != old.level) {
      await signalService?.emitProjectLevelSet(updated, old.level);
    }
    if (cycleMonths != null && cycleMonths != old.cycleMonths) {
      await signalService?.emitProjectCycleSet(updated, old.cycleMonths);
    }
    if (timeConstraint != null && timeConstraint != old.timeConstraint) {
      await signalService?.emitProjectTimeSet(updated, old.timeConstraint);
    }

    afterProjectMutation();
    // 06 轮：不再自动触发重规划，由 UI 层通过评估→规划流程驱动
  }

  /// 删除项目 → 级联删除月卡 + 系统 todo。
  Future<void> deleteProject(String id) async {
    final projectTodos = todoItems
        .where((todo) => todo.projectId == id)
        .toList(growable: false);
    for (final todo in projectTodos) {
      await onProjectTodoDeleted(todo);
    }
    await onProjectDeleted(id);
    projectList.removeWhere((p) => p.id == id);
    monthCardList.removeWhere((m) => m.projectId == id);
    todoItems.removeWhere(
      (t) => t.source == TodoSource.system && t.projectId == id,
    );
    if (currentProjectId == id) {
      currentProjectId = projectList.isNotEmpty ? projectList.first.id : null;
    }
    afterProjectMutation();
  }

  /// 切换当前项目。
  void selectProject(String id) {
    currentProjectId = id;
    afterProjectMutation();
  }

  // ---------------------------------------------------------------------------
  // 月卡 CRUD
  // ---------------------------------------------------------------------------

  /// 维护从今天开始的 7 天滚动项目计划。
  ///
  /// 已存在的系统事项、用户编辑和完成状态都不覆盖；每天只补入新的第 8 天。
  Future<void> checkAndGenerateDaily() async {
    final svc = structuredAi;
    final todayDate = DateTime.now();
    final beforeCount = todoItems.length;
    final todayKey = dateKey(todayDate);
    final beforeTodayCount = todoItems
        .where((todo) => todo.date == todayKey)
        .length;

    for (final project in List<Project>.of(projectList)) {
      // 跳过没有 goal 的项目（不触发 AI 规划）
      if (project.goal.isEmpty) continue;

      // 检查是否跨月 → 需要先结算再披露新月卡
      final currentCard = monthCardList.cast<MonthCard?>().firstWhere(
        (m) =>
            m?.projectId == project.id &&
            m?.monthIndex == project.currentMonthIndex,
        orElse: () => null,
      );
      if (currentCard == null) {
        for (final date in DailyPlanningPolicy.missingSystemDates(
          todos: todoItems,
          projectId: project.id,
          today: todayDate,
        )) {
          _addSystemTodoForDate(
            title: '开始学习 ${project.name}',
            date: date,
            projectId: project.id,
          );
        }
        continue;
      }

      // 计算该月卡对应的真实日期范围
      final projectStart = project.createdAt;
      final cardMonth = projectStart.month + project.currentMonthIndex;
      final cardYear = projectStart.year + (cardMonth - 1) ~/ 12;
      final actualCardMonth = (cardMonth - 1) % 12 + 1;
      final actualCardYear = cardYear;

      // 检查今天是否在当前月卡对应的真实月份内
      if (todayDate.month == actualCardMonth &&
          todayDate.year == actualCardYear) {
        // 当月月卡期内，生成每日 todo
      } else if (todayDate.isAfter(
        DateTime(actualCardYear, actualCardMonth + 1, 0),
      )) {
        // 已过该月 → advance 并改用新月卡生成任务
        final nextMonthIndex = project.currentMonthIndex + 1;
        if (nextMonthIndex < project.cycleMonths) {
          updateProject(project.id, currentMonthIndex: nextMonthIndex);
          final newCard = DailyPlanningPolicy.cardForMonth(
            cards: monthCardList,
            projectId: project.id,
            monthIndex: nextMonthIndex,
          );
          await _fillRollingWindowForProject(svc, project, todayDate, newCard);
        }
        continue;
      }

      await _fillRollingWindowForProject(svc, project, todayDate, currentCard);
    }

    if (todoItems.length != beforeCount) {
      final afterTodayCount = todoItems
          .where((todo) => todo.date == todayKey)
          .length;
      afterProjectMutation(
        affectsTodayLoad: beforeTodayCount != afterTodayCount,
      );
    }

    // 每次日检后裁剪旧信号，防止信号表无限增长
    signalDb?.pruneOldSignals(keepCount: 200);
  }

  Future<void> _fillRollingWindowForProject(
    StructuredGenerationCapability? svc,
    Project project,
    DateTime today,
    MonthCard? currentCard,
  ) async {
    final datesByCard = <String, List<String>>{};
    final cardsByKey = <String, MonthCard?>{};
    for (final date in DailyPlanningPolicy.missingSystemDates(
      todos: todoItems,
      projectId: project.id,
      today: today,
    )) {
      final targetMonthIndex = DailyPlanningPolicy.monthIndexForDate(
        projectStart: project.createdAt,
        date: DateTime.parse(date),
      );
      if (targetMonthIndex < 0 || targetMonthIndex >= project.cycleMonths) {
        continue;
      }
      final targetCard =
          targetMonthIndex >= 0 && targetMonthIndex < project.cycleMonths
          ? DailyPlanningPolicy.cardForMonth(
              cards: monthCardList,
              projectId: project.id,
              monthIndex: targetMonthIndex,
            )
          : null;
      final card = targetCard ?? currentCard;
      final key = card?.id ?? 'fallback-$targetMonthIndex';
      cardsByKey[key] = card;
      datesByCard.putIfAbsent(key, () => []).add(date);
    }

    for (final entry in datesByCard.entries) {
      final card = cardsByKey[entry.key];
      final dates = entry.value;
      if (svc == null || card == null || card.title.isEmpty) {
        for (final date in dates) {
          await _generateDailyTodoForProject(null, project, date, card);
        }
        continue;
      }
      final scheduledHours = DailyPlanningPolicy.scheduledCountForWeek(
        todos: todoItems,
        projectId: project.id,
        today: today,
      );
      final result = await svc.generateWeeklyTodos(
        monthPlanTitle: card.title,
        monthPlanSummary: card.summary ?? '',
        dates: dates,
        timeConstraint: project.timeConstraint > 0 ? project.timeConstraint : 7,
        scheduledHours: scheduledHours,
      );
      if (result == null) {
        for (final date in dates) {
          await _generateDailyTodoForProject(null, project, date, card);
        }
        continue;
      }
      for (final date in dates) {
        final seeds = result.todosByDate[date] ?? const <TodoSeed>[];
        if (seeds.isEmpty) {
          _addSystemTodoForDate(
            title: '继续学习 ${project.name}',
            date: date,
            projectId: project.id,
          );
          continue;
        }
        for (final seed in seeds) {
          _addSystemTodoForDate(
            title: seed.title,
            body: seed.body,
            date: date,
            projectId: project.id,
          );
        }
      }
    }
  }

  Future<void> _generateDailyTodoForProject(
    StructuredGenerationCapability? svc,
    Project project,
    String today,
    MonthCard? currentCard,
  ) async {
    // 计算本周已安排的系统 todo 数量（作为简单代理，避免历史累积偏差）
    final todayDate = DateTime.parse(today);
    final scheduledHours = DailyPlanningPolicy.scheduledCountForWeek(
      todos: todoItems,
      projectId: project.id,
      today: todayDate,
    );

    // 如果月卡为空或标题为空，生成一个基础 todo
    if (currentCard == null || currentCard.title.isEmpty) {
      _addSystemTodoForDate(
        title: '开始学习 ${project.name}',
        date: today,
        projectId: project.id,
      );
      return;
    }

    final result = svc == null
        ? null
        : await svc.generateDailyTodos(
            monthPlanTitle: currentCard.title,
            monthPlanSummary: currentCard.summary ?? '',
            date: today,
            timeConstraint: project.timeConstraint > 0
                ? project.timeConstraint
                : 7,
            scheduledHours: scheduledHours,
          );

    if (result == null) {
      // 生成失败 → 降级为基础 todo
      _addSystemTodoForDate(
        title: '继续学习 ${project.name}',
        date: today,
        projectId: project.id,
      );
      return;
    }

    for (final seed in result.todos) {
      _addSystemTodoForDate(
        title: seed.title,
        body: seed.body,
        date: seed.date.isNotEmpty ? seed.date : today,
        projectId: project.id,
      );
    }
  }

  /// 将内存中的项目生成请求一次性提交到领域状态。
  Future<void> commitProjectPlan(
    ProjectGenerationRequest request,
    GoalAssessment? assessment,
    PlanResult plan,
  ) async {
    final projectId = request.existingProjectId ?? request.projectId;
    final existingIndex = projectList.indexWhere((p) => p.id == projectId);
    final existing = existingIndex == -1 ? null : projectList[existingIndex];
    final summary = assessment?.goalSummary.trim() ?? '';
    final plannedTitle = plan.projectTitle.trim();
    final fallbackName = request.goal.length <= 16
        ? request.goal
        : request.goal.substring(0, 16);
    final name = summary.isNotEmpty
        ? summary
        : plannedTitle.length >= 2 && plannedTitle.length <= 16
        ? plannedTitle
        : existing != null && existing.name.trim().isNotEmpty
        ? existing.name
        : fallbackName;
    final assessmentJson = assessment == null
        ? null
        : jsonEncode(assessment.toJson());

    final updated = Project(
      id: projectId,
      name: name,
      color: request.color,
      goal: request.goal,
      level: request.level,
      cycleMonths: request.cycleMonths,
      timeConstraint: request.timeConstraint,
      currentMonthIndex: 0,
      createdAt: existing?.createdAt ?? DateTime.now(),
      lastAssessmentJson: assessmentJson ?? existing?.lastAssessmentJson,
      goalSummary: name,
    );
    if (existingIndex == -1) {
      projectList.add(updated);
    } else {
      projectList[existingIndex] = updated;
    }
    currentProjectId = projectId;

    monthCardList.removeWhere((card) => card.projectId == projectId);
    for (final monthPlan in plan.monthPlans) {
      monthCardList.add(
        MonthCard(
          id: newSumiId('mc'),
          projectId: projectId,
          monthIndex: monthPlan.monthIndex,
          title: monthPlan.title,
          summary: monthPlan.summary,
          aiGenerated: true,
        ),
      );
    }
    for (final seed in plan.todayTodos) {
      _addSystemTodoForDate(
        title: seed.title,
        body: seed.body,
        date: seed.date,
        projectId: projectId,
      );
    }

    await signalService?.emitProjectGoalSet(updated, existing?.goal);
    afterProjectMutation(scheduleRollingPlanning: false);
  }

  /// 添加系统 todo（指定日期），去重检查。
  void _addSystemTodoForDate({
    required String title,
    String? body,
    required String date,
    required String projectId,
  }) {
    if (title.trim().isEmpty) return;
    // 去重：同日同项目同标题不重复添加
    final exists = todoItems.any(
      (t) =>
          t.source == TodoSource.system &&
          t.projectId == projectId &&
          t.date == date &&
          t.title == title.trim(),
    );
    if (exists) return;

    final nextOrder = 0; // system todo 在末尾
    todoItems.add(
      TodoItem(
        id: newSumiId('todo'),
        source: TodoSource.system,
        projectId: projectId,
        date: date,
        title: title.trim(),
        body: body,
        sortOrder: nextOrder,
        createdAt: DateTime.now(),
      ),
    );
  }

  // ——— 便捷查询 ———

  List<Project> get projects => List.unmodifiable(projectList);

  Project? get currentProject {
    if (currentProjectId == null) return null;
    try {
      return projectList.firstWhere((p) => p.id == currentProjectId);
    } catch (_) {
      return null;
    }
  }

  List<MonthCard> monthCardsFor(String projectId) =>
      monthCardList.where((m) => m.projectId == projectId).toList();

  /// 找到下一个可用的项目色。
  ProjectColor nextAvailableColor() {
    final used = projectList.map((p) => p.color).toSet();
    for (final c in ProjectColor.values) {
      if (!used.contains(c)) return c;
    }
    return ProjectColor.lemon;
  }
}
