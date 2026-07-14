part of 'sumi_store.dart';

// ---------------------------------------------------------------------------
// Project & MonthCard Mutations mixin
// ---------------------------------------------------------------------------

mixin SumiStoreProjects on ChangeNotifier {
  List<Project> get projectList;
  List<MonthCard> get monthCardList;
  List<TodoItem> get todoItems;
  String? get currentProjectId;
  set currentProjectId(String? v);
  AiService? get aiService;
  void afterMutation();

  // ---------------------------------------------------------------------------
  // 创建项目（改造：创建后触发 AI 规划）
  // ---------------------------------------------------------------------------

  /// 新建项目（06 轮：不再自动触发规划，由 UI 层通过评估流程驱动）。
  void addProject({
    required String name,
    required ProjectColor color,
    String goal = '',
    String level = '',
    int cycleMonths = 3,
    int timeConstraint = 0,
  }) {
    final projId = newSumiId('proj');
    projectList.add(Project(
      id: projId,
      name: name,
      color: color,
      goal: goal,
      level: level,
      cycleMonths: cycleMonths,
      timeConstraint: timeConstraint,
      currentMonthIndex: 0,
      createdAt: DateTime.now(),
    ));
    // 自动生成 cycleMonths 张空月卡
    for (var i = 0; i < cycleMonths; i++) {
      monthCardList.add(MonthCard(
        id: newSumiId('mc'),
        projectId: projId,
        monthIndex: i,
        title: '',
      ));
    }
    if (currentProjectId == null) {
      currentProjectId = projectList.last.id;
    }
    afterMutation();
    // 06 轮：不再自动触发 AI 规划，由 UI 层通过评估→规划流程驱动
  }

  /// 新建项目草稿（06 轮新增）—— 不创建月卡，不触发规划。
  /// 月卡由 [commitPlan] 在评估+规划完成后一次性写入。
  String addProjectDraft({
    required String name,
    required ProjectColor color,
    String goal = '',
    String level = '',
    int cycleMonths = 3,
    int timeConstraint = 0,
  }) {
    final projId = newSumiId('proj');
    projectList.add(Project(
      id: projId,
      name: name,
      color: color,
      goal: goal,
      level: level,
      cycleMonths: cycleMonths,
      timeConstraint: timeConstraint,
      currentMonthIndex: 0,
      createdAt: DateTime.now(),
    ));
    // 不创建月卡 —— 等 commitPlan 一次性写入
    if (currentProjectId == null) {
      currentProjectId = projId;
    }
    afterMutation();
    return projId;
  }

  /// 更新项目字段。编辑保存后，若影响规划的字段变更则自动重新规划。
  void updateProject(String id, {
    String? name,
    ProjectColor? color,
    String? goal,
    String? level,
    int? cycleMonths,
    int? timeConstraint,
    int? currentMonthIndex,
  }) {
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
    );
    // 如果 cycleMonths 变更，调整月卡数量
    if (cycleMonths != null && cycleMonths != oldCycle) {
      if (cycleMonths > oldCycle) {
        for (var m = oldCycle; m < cycleMonths; m++) {
          monthCardList.add(MonthCard(
            id: newSumiId('mc'),
            projectId: id,
            monthIndex: m,
            title: '',
          ));
        }
      } else {
        monthCardList.removeWhere(
          (mc) => mc.projectId == id && mc.monthIndex >= cycleMonths,
        );
      }
    }
    afterMutation();
    // 06 轮：不再自动触发重规划，由 UI 层通过评估→规划流程驱动
  }

  /// 删除项目 → 级联删除月卡 + 系统 todo。
  void deleteProject(String id) {
    projectList.removeWhere((p) => p.id == id);
    monthCardList.removeWhere((m) => m.projectId == id);
    todoItems.removeWhere(
        (t) => t.source == TodoSource.system && t.projectId == id);
    if (currentProjectId == id) {
      currentProjectId = projectList.isNotEmpty ? projectList.first.id : null;
    }
    afterMutation();
  }

  /// 切换当前项目。
  void selectProject(String id) {
    currentProjectId = id;
    afterMutation();
  }

  // ---------------------------------------------------------------------------
  // 月卡 CRUD
  // ---------------------------------------------------------------------------

  /// 更新月卡。
  void updateMonthCard(String id, {String? title, String? summary, bool? aiGenerated}) {
    final i = monthCardList.indexWhere((m) => m.id == id);
    if (i == -1) return;
    monthCardList[i] = monthCardList[i].copyWith(
      title: title,
      summary: summary,
      aiGenerated: aiGenerated,
    );
    afterMutation();
  }

  /// 当前项目进度 +1（不超过 cycleMonths）。
  void advanceCurrentMonth() {
    final project = currentProject;
    if (project == null) return;
    final next = project.currentMonthIndex + 1;
    if (next >= project.cycleMonths) return;
    updateProject(project.id, currentMonthIndex: next);
  }

  // ---------------------------------------------------------------------------
  // AI 规划
  // ---------------------------------------------------------------------------

  /// 触发 AI 规划（异步，不阻塞 UI）。
  Future<void> _triggerPlanning(String projectId) async {
    final svc = aiService;
    if (svc == null) return;

    // 查找项目
    final pi = projectList.indexWhere((p) => p.id == projectId);
    if (pi == -1) return;
    final project = projectList[pi];

    final startDate = dateKey(DateTime.now());

    // 联网搜索补充上下文（Tavily）
    String? searchContext;
    try {
      final searchResults = await svc.searchWeb(project.goal);
      if (searchResults.isNotEmpty &&
          !searchResults.first.containsKey('error') &&
          !searchResults.first.containsKey('info')) {
        final buf = StringBuffer();
        for (final r in searchResults) {
          buf.writeln('- **${r['title']}**');
          buf.writeln('  ${r['content']}');
          buf.writeln('  来源：${r['url']}');
          buf.writeln();
        }
        searchContext = buf.toString();
      }
    } catch (_) {
      // Tavily 不可用时静默回退，不影响规划流程
    }

    final result = await svc.generateProjectPlan(
      goal: project.goal,
      level: project.level,
      cycleMonths: project.cycleMonths,
      timeConstraint: project.timeConstraint,
      startDate: startDate,
      searchContext: searchContext,
    );

    if (result == null) {
      // 规划失败 —— 静默，月卡保持空白
      return;
    }

    // 更新月卡
    for (final plan in result.monthPlans) {
      final mi = monthCardList.indexWhere(
        (m) => m.projectId == projectId && m.monthIndex == plan.monthIndex,
      );
      if (mi != -1) {
        monthCardList[mi] = monthCardList[mi].copyWith(
          title: plan.title,
          summary: plan.summary,
          aiGenerated: true,
        );
      }
    }

    // 创建当天系统 todo
    for (final seed in result.todayTodos) {
      _addSystemTodoForDate(
        title: seed.title,
        body: seed.body,
        date: seed.date,
        projectId: projectId,
      );
    }

    afterMutation();
  }

  /// 检测并生成每日 todo（App 启动时调用）。
  Future<void> checkAndGenerateDaily() async {
    final svc = aiService;
    if (svc == null) return;

    final today = dateKey(DateTime.now());
    final todayDate = DateTime.now();

    for (final project in List<Project>.of(projectList)) {
      // 跳过没有 goal 的项目（不触发 AI 规划）
      if (project.goal.isEmpty) continue;

      // 检查今天是否已有该项目的系统 todo
      final hasTodayTodo = todoItems.any(
        (t) =>
            t.source == TodoSource.system &&
            t.projectId == project.id &&
            t.date == today,
      );
      if (hasTodayTodo) continue;

      // 检查是否跨月 → 需要先结算再披露新月卡
      final currentCard = monthCardList.cast<MonthCard?>().firstWhere(
        (m) => m?.projectId == project.id && m?.monthIndex == project.currentMonthIndex,
        orElse: () => null,
      );
      if (currentCard == null) {
        // 没有当前月卡，生成基础 todo
        _addSystemTodoForDate(
          title: '开始学习 ${project.name}',
          date: today,
          projectId: project.id,
        );
        continue;
      }

      // 计算该月卡对应的真实日期范围
      final projectStart = project.createdAt;
      final cardMonth = projectStart.month + project.currentMonthIndex;
      final cardYear = projectStart.year + (cardMonth - 1) ~/ 12;
      final actualCardMonth = (cardMonth - 1) % 12 + 1;
      final actualCardYear = cardYear;

      // 检查今天是新月第一天
      if (todayDate.month == actualCardMonth && todayDate.year == actualCardYear) {
        // 当月月卡期内，生成每日 todo
      } else if (todayDate.isAfter(DateTime(actualCardYear, actualCardMonth + 1, 0))) {
        // 已过该月 → advance 并重新检测
        advanceCurrentMonth();
        // 重新生成（递归一次）
        await _generateDailyTodoForProject(
          svc, project, today, currentCard,
        );
        continue;
      }

      // 生成每日 todo
      await _generateDailyTodoForProject(svc, project, today, currentCard);
    }

    afterMutation();
  }

  Future<void> _generateDailyTodoForProject(
    AiService svc,
    Project project,
    String today,
    MonthCard currentCard,
  ) async {
    // 计算本周已安排的 todo 数量（作为简单代理）
    final scheduledHours = todoItems
        .where((t) =>
            t.source == TodoSource.system &&
            t.projectId == project.id &&
            t.date != null)
        .length;

    // 如果月卡标题为空，生成一个基础 todo
    if (currentCard.title.isEmpty) {
      _addSystemTodoForDate(
        title: '开始学习 ${project.name}',
        date: today,
        projectId: project.id,
      );
      return;
    }

    final result = await svc.generateDailyTodos(
      monthPlanTitle: currentCard.title,
      monthPlanSummary: currentCard.summary ?? '',
      date: today,
      timeConstraint: project.timeConstraint > 0 ? project.timeConstraint : 7,
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

  /// 规划完成后一次性提交（06 轮新增）。
  /// 写入月卡 + 首日 todo，完成后触发 UI 刷新。
  void commitPlan(String projectId, PlanResult plan) {
    // 清除该项目的旧月卡（如果有）
    monthCardList.removeWhere((m) => m.projectId == projectId);

    // 写入新月卡
    for (final monthPlan in plan.monthPlans) {
      monthCardList.add(MonthCard(
        id: newSumiId('mc'),
        projectId: projectId,
        monthIndex: monthPlan.monthIndex,
        title: monthPlan.title,
        summary: monthPlan.summary,
        aiGenerated: true,
      ));
    }

    // 写入首日 todo
    for (final seed in plan.todayTodos) {
      _addSystemTodoForDate(
        title: seed.title,
        body: seed.body,
        date: seed.date,
        projectId: projectId,
      );
    }

    afterMutation();
  }

  /// 手动重试规划。
  Future<void> retryPlanning(String projectId) async {
    // 清除旧 AI 月卡内容
    for (var i = 0; i < monthCardList.length; i++) {
      if (monthCardList[i].projectId == projectId && monthCardList[i].aiGenerated) {
        monthCardList[i] = monthCardList[i].copyWith(
          title: '',
          summary: null,
          aiGenerated: false,
        );
      }
    }
    afterMutation();
    await _triggerPlanning(projectId);
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

  List<MonthCard> get monthCards => List.unmodifiable(monthCardList);

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
