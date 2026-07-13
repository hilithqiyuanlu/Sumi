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
  void afterMutation();

  /// 新建项目（校验 ≤3）。
  void addProject({
    required String name,
    required ProjectColor color,
    String goal = '',
    String level = '',
    int cycleMonths = 3,
    String timeConstraint = '',
  }) {
    if (projectList.length >= 3) return;
    projectList.add(Project(
      id: newSumiId('proj'),
      name: name,
      color: color,
      goal: goal,
      level: level,
      cycleMonths: cycleMonths,
      timeConstraint: timeConstraint,
      currentMonthIndex: 0,
      createdAt: DateTime.now(),
    ));
    if (currentProjectId == null) {
      currentProjectId = projectList.last.id;
    }
    afterMutation();
  }

  /// 更新项目字段。
  void updateProject(String id, {
    String? name,
    ProjectColor? color,
    String? goal,
    String? level,
    int? cycleMonths,
    String? timeConstraint,
    int? currentMonthIndex,
  }) {
    final i = projectList.indexWhere((p) => p.id == id);
    if (i == -1) return;
    projectList[i] = projectList[i].copyWith(
      name: name,
      color: color,
      goal: goal,
      level: level,
      cycleMonths: cycleMonths,
      timeConstraint: timeConstraint,
      currentMonthIndex: currentMonthIndex,
    );
    afterMutation();
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

  /// 添加月卡。
  void addMonthCard({
    required String projectId,
    required int monthIndex,
    required String title,
    String? summary,
  }) {
    monthCardList.add(MonthCard(
      id: newSumiId('mc'),
      projectId: projectId,
      monthIndex: monthIndex,
      title: title,
      summary: summary,
    ));
    afterMutation();
  }

  /// 更新月卡。
  void updateMonthCard(String id, {String? title, String? summary}) {
    final i = monthCardList.indexWhere((m) => m.id == id);
    if (i == -1) return;
    monthCardList[i] = monthCardList[i].copyWith(title: title, summary: summary);
    afterMutation();
  }

  /// 删除月卡。
  void deleteMonthCard(String id) {
    monthCardList.removeWhere((m) => m.id == id);
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

  bool get canAddProject => projectList.length < 3;

  /// 找到下一个可用的项目色。
  ProjectColor nextAvailableColor() {
    final used = projectList.map((p) => p.color).toSet();
    for (final c in ProjectColor.values) {
      if (!used.contains(c)) return c;
    }
    return ProjectColor.lemon;
  }
}
