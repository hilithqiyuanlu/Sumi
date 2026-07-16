typedef AiMapValidator = AiContractValidation<Map<String, Object?>> Function(
  Map<String, Object?> value,
);

class AiContractValidation<T> {
  final T? value;
  final List<String> errors;

  const AiContractValidation.valid(this.value) : errors = const [];
  const AiContractValidation.invalid(this.errors) : value = null;

  bool get isValid => errors.isEmpty && value != null;
}

class AiContracts {
  const AiContracts._();

  static AiContractValidation<Map<String, Object?>> split(
    Map<String, Object?> value,
  ) {
    final split = value['split'];
    final rawItems = value['items'];
    final errors = <String>[];
    if (split is! bool) errors.add('split 必须是布尔值');
    final items = _stringList(rawItems, 'items', errors);
    if (items.isEmpty || items.length > 10) {
      errors.add('items 数量必须为 1-10');
    }
    for (final item in items) {
      if (!_lengthBetween(item, 2, 16)) {
        errors.add('每个事项标题必须为 2-16 字');
        break;
      }
    }
    if (split == false && items.length != 1) {
      errors.add('split=false 时 items 必须只有一项');
    }
    if (errors.isNotEmpty) return AiContractValidation.invalid(errors);
    return AiContractValidation.valid({'split': split, 'items': items});
  }

  static AiContractValidation<String> polishedText(String value) {
    var text = value.trim();
    if ((text.startsWith('"') && text.endsWith('"')) ||
        (text.startsWith("'") && text.endsWith("'"))) {
      text = text.substring(1, text.length - 1).trim();
    }
    if (!_lengthBetween(text, 2, 16) ||
        text.contains('\n') ||
        RegExp(r'[`*_#{}\[\]]').hasMatch(text)) {
      return const AiContractValidation.invalid(['润色结果必须是 2-16 字的单行纯文本']);
    }
    return AiContractValidation.valid(text);
  }

  static AiContractValidation<Map<String, Object?>> plan(
    Map<String, Object?> value, {
    required int cycleMonths,
    required String startDate,
  }) {
    final errors = <String>[];
    final rawMonths = value['monthPlans'];
    final rawTodos = value['todayTodos'];
    if (rawMonths is! List<Object?>) errors.add('monthPlans 必须是数组');
    if (rawTodos is! List<Object?>) errors.add('todayTodos 必须是数组');
    if (errors.isNotEmpty) return AiContractValidation.invalid(errors);

    final months = <Map<String, Object?>>[];
    final indexes = <int>{};
    for (final raw in rawMonths as List<Object?>) {
      if (raw is! Map<String, Object?>) {
        errors.add('monthPlans 每项必须是对象');
        continue;
      }
      final index = _integer(raw['monthIndex']);
      final title = _text(raw['title']);
      final summary = _text(raw['summary']);
      if (index == null || index < 0 || index >= cycleMonths) {
        errors.add('monthIndex 必须在 0-${cycleMonths - 1} 范围内');
      } else if (!indexes.add(index)) {
        errors.add('monthIndex 不能重复');
      }
      if (!_lengthBetween(title, 2, 10)) {
        errors.add('月计划标题必须为 2-10 字');
      }
      if (!_lengthBetween(summary, 30, 120)) {
        errors.add('月计划摘要必须为 30-120 字');
      }
      months.add({'monthIndex': index, 'title': title, 'summary': summary});
    }
    if (months.length != cycleMonths || indexes.length != cycleMonths) {
      errors.add('月计划数量和索引必须完整覆盖 $cycleMonths 个月');
    }
    final rawProjectTitle = _text(value['projectTitle']);
    if (rawProjectTitle.isNotEmpty && !_lengthBetween(rawProjectTitle, 2, 16)) {
      errors.add('项目标题必须为 2-16 字');
    }
    final projectTitle = rawProjectTitle.isNotEmpty
        ? rawProjectTitle
        : months.isEmpty
        ? ''
        : _text(months.first['title']);

    final todos = _todoSeeds(
      rawTodos as List<Object?>,
      errors,
      expectedDate: startDate,
      minItems: 1,
      maxItems: 2,
    );
    if (errors.isNotEmpty) return AiContractValidation.invalid(errors);
    return AiContractValidation.valid({
      'projectTitle': projectTitle,
      'monthPlans': months,
      'todayTodos': todos,
    });
  }

  static AiContractValidation<Map<String, Object?>> dailyTodos(
    Map<String, Object?> value, {
    required String date,
  }) {
    final errors = <String>[];
    final rawTodos = value['todos'];
    if (rawTodos is! List<Object?>) {
      return const AiContractValidation.invalid(['todos 必须是数组']);
    }
    final todos = _todoSeeds(
      rawTodos,
      errors,
      expectedDate: date,
      minItems: 0,
      maxItems: 3,
    );
    if (errors.isNotEmpty) return AiContractValidation.invalid(errors);
    return AiContractValidation.valid({'todos': todos});
  }

  static AiContractValidation<Map<String, Object?>> weeklyTodos(
    Map<String, Object?> value, {
    required List<String> dates,
  }) {
    final rawDays = value['days'];
    if (rawDays is! List<Object?>) {
      return const AiContractValidation.invalid(['days 必须是数组']);
    }
    final expected = dates.toSet();
    final seen = <String>{};
    final days = <Map<String, Object?>>[];
    final errors = <String>[];
    for (final raw in rawDays) {
      if (raw is! Map<String, Object?>) {
        errors.add('days 每项必须是对象');
        continue;
      }
      final date = _text(raw['date']);
      if (!expected.contains(date) || !seen.add(date)) {
        errors.add('days 必须与请求日期一一对应');
        continue;
      }
      if (raw['todos'] is! List<Object?>) {
        errors.add('$date 的 todos 必须是数组');
        continue;
      }
      final todos = _todoSeeds(
        raw['todos'] as List<Object?>,
        errors,
        expectedDate: date,
        minItems: 0,
        maxItems: 3,
      );
      days.add({'date': date, 'todos': todos});
    }
    if (seen.length != expected.length) errors.add('days 必须完整覆盖请求日期');
    if (errors.isNotEmpty) return AiContractValidation.invalid(errors);
    return AiContractValidation.valid({'days': days});
  }

  static AiContractValidation<Map<String, Object?>> todayLoad(
    Map<String, Object?> value, {
    required Set<String> validTodoIds,
    required Set<String> futureDates,
  }) {
    final risk = _finiteDouble(value['risk']);
    final reasons = _stringList(value['reasons'], 'reasons', <String>[]);
    final suggestion = _text(value['suggestion']);
    final rawIds = value['movableTodoIds'];
    final rawPressure = value['futureDayPressure'];
    final errors = <String>[];
    if (risk == null || risk < 0 || risk > 1) {
      errors.add('risk 必须是 0-1 的有限数值');
    }
    if (reasons.isEmpty ||
        reasons.length > 3 ||
        reasons.any((item) => !_lengthBetween(item, 4, 80))) {
      errors.add('reasons 必须是 1-3 条 4-80 字原因');
    }
    if (!_lengthBetween(suggestion, 4, 80)) {
      errors.add('suggestion 必须是 4-80 字');
    }
    if (rawIds is! List<Object?> || rawIds.any((id) => id is! String)) {
      errors.add('movableTodoIds 必须是字符串数组');
    }
    final ids = rawIds is List<Object?>
        ? rawIds.whereType<String>().toList(growable: false)
        : const <String>[];
    if (ids.toSet().length != ids.length ||
        ids.any((id) => !validTodoIds.contains(id))) {
      errors.add('movableTodoIds 包含无效事项');
    }
    if (rawPressure is! List<Object?>) {
      errors.add('futureDayPressure 必须是数组');
    }
    final pressures = <Map<String, Object?>>[];
    final pressureDates = <String>{};
    if (rawPressure is List<Object?>) {
      for (final raw in rawPressure) {
        if (raw is! Map<String, Object?>) {
          errors.add('futureDayPressure 每项必须是对象');
          continue;
        }
        final date = _text(raw['date']);
        final pressure = _finiteDouble(raw['pressure']);
        if (!futureDates.contains(date) ||
            !pressureDates.add(date) ||
            pressure == null ||
            pressure < 0 ||
            pressure > 1) {
          errors.add('futureDayPressure 必须完整覆盖输入日期且压力在 0-1');
          continue;
        }
        pressures.add({'date': date, 'pressure': pressure});
      }
    }
    if (pressureDates.length != futureDates.length) {
      errors.add('futureDayPressure 必须完整覆盖输入日期');
    }
    if (errors.isNotEmpty) return AiContractValidation.invalid(errors);
    return AiContractValidation.valid({
      'risk': risk,
      'reasons': reasons,
      'suggestion': suggestion,
      'movableTodoIds': ids,
      'futureDayPressure': pressures,
    });
  }

  static AiContractValidation<Map<String, Object?>> todayLoadScreening(
    Map<String, Object?> value,
  ) {
    final errors = <String>[];
    final risk = _finiteDouble(value['risk']);
    final reasons = _stringList(value['reasons'], 'reasons', errors);
    if (risk == null || risk < 0 || risk > 1) {
      errors.add('risk 必须是 0-1 的有限数值');
    }
    if (reasons.isEmpty ||
        reasons.length > 3 ||
        reasons.any((item) => !_lengthBetween(item, 4, 80))) {
      errors.add('reasons 必须是 1-3 条 4-80 字原因');
    }
    if (errors.isNotEmpty) return AiContractValidation.invalid(errors);
    return AiContractValidation.valid({'risk': risk, 'reasons': reasons});
  }

  static AiContractValidation<Map<String, Object?>> assessment(
    Map<String, Object?> value,
  ) {
    const scoreKeys = [
      'clarity',
      'feasibility',
      'challengeFit',
      'decomposability',
      'timeRealism',
      'motivationPotential',
      'resourceAccess',
      'measurability',
    ];
    final errors = <String>[];
    final normalized = <String, Object?>{};
    for (final key in scoreKeys) {
      final score = _finiteDouble(value[key]);
      if (score == null || score < 0 || score > 1) {
        errors.add('$key 必须是 0-1 的有限数值');
      } else {
        normalized[key] = score;
      }
    }
    final verdict = _text(value['verdict']).toLowerCase();
    if (!const {'a', 'b', 'c', 'd'}.contains(verdict)) {
      errors.add('verdict 必须是 a、b、c 或 d');
    }
    final concerns = _stringList(value['concerns'], 'concerns', errors);
    final suggestions = _stringList(
      value['suggestions'],
      'suggestions',
      errors,
    );
    final goalSummary = _text(value['goalSummary']);
    if (!_lengthBetween(goalSummary, 2, 16)) {
      errors.add('goalSummary 必须为 2-16 字');
    }
    if (errors.isNotEmpty) return AiContractValidation.invalid(errors);
    normalized.addAll({
      'verdict': verdict,
      'concerns': concerns,
      'suggestions': suggestions,
      'goalSummary': goalSummary,
      if (value['estimatedHours'] is String)
        'estimatedHours': _text(value['estimatedHours']),
      if (value['domainSummary'] is String)
        'domainSummary': _text(value['domainSummary']),
    });
    return AiContractValidation.valid(normalized);
  }

  static AiContractValidation<Map<String, Object?>> suggestions(
    Map<String, Object?> value,
  ) {
    final errors = <String>[];
    final items = _stringList(value['suggestions'], 'suggestions', errors);
    if (items.length < 3 || items.length > 4) {
      errors.add('建议数量必须为 3-4');
    }
    if (items.toSet().length != items.length) errors.add('建议不能重复');
    for (final item in items) {
      if (!_lengthBetween(item, 8, 20)) {
        errors.add('每条建议必须为 8-20 字');
        break;
      }
    }
    if (errors.isNotEmpty) return AiContractValidation.invalid(errors);
    return AiContractValidation.valid({'suggestions': items});
  }

  static AiContractValidation<Map<String, Object?>> memoryExtraction(
    Map<String, Object?> value,
  ) {
    final action = _text(value['action']).toLowerCase();
    if (!const {'ignore', 'save', 'replace'}.contains(action)) {
      return const AiContractValidation.invalid([
        'action 必须是 ignore、save 或 replace',
      ]);
    }
    if (action == 'ignore') {
      return const AiContractValidation.valid({'action': 'ignore'});
    }
    final type = _text(value['type']).isEmpty
        ? 'explicit'
        : _text(value['type']);
    final category = _text(value['category']);
    final content = _text(value['content']);
    final quotedText = _text(value['quotedText']);
    final errors = <String>[];
    if (!const {'explicit', 'current'}.contains(type)) {
      errors.add('type 必须是 explicit 或 current');
    }
    final validCategories = type == 'current'
        ? const {'progress', 'difficulty', 'short_term_constraint'}
        : const {'preference', 'goal', 'constraint'};
    if (!validCategories.contains(category)) {
      errors.add('category 与 type 不匹配');
    }
    if (!_lengthBetween(content, 2, 200)) {
      errors.add('content 必须为 2-200 字');
    }
    if (!_lengthBetween(quotedText, 1, 500)) {
      errors.add('quotedText 必须为 1-500 字');
    }
    final replacesId = _text(value['replacesId']);
    if (action == 'replace' && replacesId.isEmpty) {
      errors.add('replace 必须提供 replacesId');
    }
    if (action == 'save' && replacesId.isNotEmpty) {
      errors.add('save 不能提供 replacesId');
    }
    if (errors.isNotEmpty) return AiContractValidation.invalid(errors);
    return AiContractValidation.valid({
      'action': action,
      'type': type,
      'category': category,
      'content': content,
      'quotedText': quotedText,
      if (action == 'replace') 'replacesId': replacesId,
    });
  }

  static AiContractValidation<Map<String, Object?>> toolCall(
    String id,
    String name,
    Map<String, Object?> args, {
    required Set<String> validProjectIds,
    required Set<String> enabledTools,
  }) {
    final errors = <String>[];
    final normalized = Map<String, Object?>.of(args);
    if (id.trim().isEmpty) errors.add('工具调用缺少 id');
    if (!enabledTools.contains(name)) errors.add('工具已关闭：$name');
    switch (name) {
      case 'search_web':
        final query = _text(args['query']);
        if (query.isEmpty || query.length > 200) {
          errors.add('query 必须为 1-200 字');
        }
        normalized['query'] = query;
      case 'read_memory':
        final query = _text(args['query']);
        if (query.length > 300) errors.add('query 不能超过 300 字');
        normalized['query'] = query;
        final memoryProjectId = args['projectId'];
        if (memoryProjectId != null && _text(memoryProjectId).isNotEmpty) {
          _validateProjectId(_text(memoryProjectId), validProjectIds, errors);
        }
        break;
      case 'read_todos':
        final filter = _text(args['filter']).isEmpty
            ? 'today'
            : _text(args['filter']);
        if (filter != 'today' &&
            filter != 'all' &&
            !filter.startsWith('project:')) {
          errors.add('filter 只能是 today、all 或 project:项目ID');
        }
        if (filter.startsWith('project:')) {
          _validateProjectId(filter.substring(8), validProjectIds, errors);
        }
        normalized['filter'] = filter;
      case 'write_todo':
        final title = _text(args['title']);
        if (!_lengthBetween(title, 2, 16)) {
          errors.add('title 必须为 2-16 字');
        }
        normalized['title'] = title;
        final date = args['date'];
        if (date != null && !_validDate(_text(date))) {
          errors.add('date 必须是有效的 YYYY-MM-DD 日期');
        }
        final projectId = args['projectId'];
        if (projectId != null && _text(projectId).isNotEmpty) {
          _validateProjectId(_text(projectId), validProjectIds, errors);
        }
        final body = args['body'];
        if (body != null && _text(body).length > 2000) {
          errors.add('body 不能超过 2000 字');
        }
      case 'read_signals':
        final type = args['type'];
        if (type != null &&
            !const {
              'todoCreated',
              'todoCompleted',
              'todoUncompleted',
              'todoDeleted',
              'todoEdited',
              'todoMovedDate',
              'projectGoalSet',
              'projectLevelSet',
              'projectCycleSet',
              'projectTimeSet',
            }.contains(_text(type))) {
          errors.add('type 不是有效的信号类型');
        }
        final range = _text(args['range']).isEmpty
            ? '7d'
            : _text(args['range']);
        if (!const {'7d', '30d', 'all'}.contains(range)) {
          errors.add('range 只能是 7d、30d 或 all');
        }
        final limit = args['limit'] == null ? 20 : _integer(args['limit']);
        if (limit == null || limit < 1 || limit > 100) {
          errors.add('limit 必须是 1-100 的整数');
        } else {
          normalized['limit'] = limit;
        }
        final projectId = args['projectId'];
        if (projectId != null && _text(projectId).isNotEmpty) {
          _validateProjectId(_text(projectId), validProjectIds, errors);
        }
        normalized['range'] = range;
      case 'create_study_timer':
        final title = _text(args['title']);
        final kind = _text(args['kind']).isEmpty
            ? 'timer'
            : _text(args['kind']);
        if (!_lengthBetween(title, 2, 32)) {
          errors.add('title 必须为 2-32 字');
        }
        if (!const {'timer', 'alarm'}.contains(kind)) {
          errors.add('kind 只能是 timer 或 alarm');
        }
        final startImmediately = args['startImmediately'];
        if (startImmediately != null && startImmediately is! bool) {
          errors.add('startImmediately 必须是布尔值');
        }
        if (kind == 'timer') {
          final minutes = _integer(args['minutes']);
          if (minutes == null || minutes < 1 || minutes > 480) {
            errors.add('timer 的 minutes 必须为 1-480 的整数');
          } else {
            normalized['minutes'] = minutes;
          }
        } else {
          final alertAt = DateTime.tryParse(_text(args['alertAt']));
          if (alertAt == null || !alertAt.isAfter(DateTime.now())) {
            errors.add('alarm 的 alertAt 必须是未来的 ISO 8601 时间');
          } else if (alertAt.difference(DateTime.now()).inDays > 366) {
            errors.add('alarm 的 alertAt 不能超过一年');
          } else {
            normalized['alertAt'] = alertAt.toIso8601String();
          }
        }
        normalized['title'] = title;
        normalized['kind'] = kind;
        normalized['startImmediately'] = startImmediately as bool? ?? false;
      case 'start_project_generation':
        final goal = _text(args['goal']);
        final level = _text(args['level']);
        final cycleMonths = _integer(args['cycleMonths']);
        final timeConstraint = _integer(args['timeConstraint']);
        if (!_lengthBetween(goal, 2, 300)) errors.add('goal 必须为 2-300 字');
        if (!_lengthBetween(level, 1, 80)) errors.add('level 必须为 1-80 字');
        if (!const {
          1,
          2,
          3,
          4,
          5,
          6,
          7,
          8,
          9,
          10,
          11,
          12,
          18,
          24,
          30,
        }.contains(cycleMonths)) {
          errors.add('cycleMonths 不是支持的周期');
        }
        if (!const {
          6,
          10,
          15,
          20,
          30,
          40,
          50,
          60,
          70,
        }.contains(timeConstraint)) {
          errors.add('timeConstraint 不是支持的每周投入');
        }
        normalized['goal'] = goal;
        normalized['level'] = level;
        if (cycleMonths != null) normalized['cycleMonths'] = cycleMonths;
        if (timeConstraint != null) {
          normalized['timeConstraint'] = timeConstraint;
        }
      default:
        errors.add('未知工具：$name');
    }
    if (errors.isNotEmpty) return AiContractValidation.invalid(errors);
    return AiContractValidation.valid(normalized);
  }

  static List<Map<String, Object?>> _todoSeeds(
    List<Object?> rawItems,
    List<String> errors, {
    required String expectedDate,
    required int minItems,
    required int maxItems,
  }) {
    if (rawItems.length < minItems || rawItems.length > maxItems) {
      errors.add('事项数量必须为 $minItems-$maxItems');
    }
    final result = <Map<String, Object?>>[];
    for (final raw in rawItems) {
      if (raw is! Map<String, Object?>) {
        errors.add('事项必须是对象');
        continue;
      }
      final title = _text(raw['title']);
      final date = _text(raw['date']);
      if (!_lengthBetween(title, 2, 16)) errors.add('事项标题必须为 2-16 字');
      if (!_validDate(date) || date != expectedDate) {
        errors.add('事项日期必须等于 $expectedDate');
      }
      result.add({
        'title': title,
        if (raw['body'] is String && _text(raw['body']).isNotEmpty)
          'body': _text(raw['body']),
        'date': date,
      });
    }
    return result;
  }

  static List<String> _stringList(
    Object? value,
    String key,
    List<String> errors,
  ) {
    if (value is! List<Object?>) {
      errors.add('$key 必须是字符串数组');
      return [];
    }
    final result = <String>[];
    for (final item in value) {
      if (item is! String || item.trim().isEmpty) {
        errors.add('$key 只能包含非空字符串');
      } else {
        result.add(item.trim());
      }
    }
    return result;
  }

  static String _text(Object? value) => value is String ? value.trim() : '';

  static int? _integer(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    return null;
  }

  static double? _finiteDouble(Object? value) {
    if (value is num && value.isFinite) return value.toDouble();
    return null;
  }

  static bool _lengthBetween(String value, int min, int max) =>
      value.length >= min && value.length <= max;

  static bool _validDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return false;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);
    return parsed.year == year && parsed.month == month && parsed.day == day;
  }

  static void _validateProjectId(
    String value,
    Set<String> validProjectIds,
    List<String> errors,
  ) {
    if (value.isEmpty || !validProjectIds.contains(value)) {
      errors.add('projectId 不存在：$value');
    }
  }
}

class ToolCallValidator {
  const ToolCallValidator._();

  static AiContractValidation<Map<String, Object?>> validate(
    String id,
    String name,
    Map<String, Object?> arguments, {
    required Set<String> validProjectIds,
    Set<String>? enabledTools,
  }) {
    return AiContracts.toolCall(
      id,
      name,
      arguments,
      validProjectIds: validProjectIds,
      enabledTools:
          enabledTools ??
          const {
            'search_web',
            'read_memory',
            'read_todos',
            'read_signals',
            'write_todo',
            'create_study_timer',
            'start_project_generation',
          },
    );
  }
}
