class ChatToolDefinition {
  final String name;
  final String label;
  final String description;
  final String group;
  final Map<String, Object?> schema;
  final bool system;

  const ChatToolDefinition({
    required this.name,
    required this.label,
    required this.description,
    required this.group,
    required this.schema,
    this.system = false,
  });
}

/// The single source of truth for chat-visible tools and their JSON schemas.
class ChatToolRegistry {
  const ChatToolRegistry._();

  static const allNames = <String>[
    'search_web',
    'read_memory',
    'read_todos',
    'read_signals',
    'write_todo',
    'move_todo_date',
    'edit_todo',
    'delete_todo',
    'toggle_todo_completion',
    'create_study_timer',
    'start_project_generation',
  ];

  static const definitions = <ChatToolDefinition>[
    ChatToolDefinition(
      name: 'search_web',
      label: '搜索资料',
      description: '需要实时信息或事实核查时搜索网络。',
      group: '读取与检索',
      schema: {
        'type': 'function',
        'function': {
          'name': 'search_web',
          'description': '搜索网络获取实时信息、事实核查或资料。',
          'parameters': {
            'type': 'object',
            'properties': {
              'query': {'type': 'string'},
            },
            'required': ['query'],
          },
        },
      },
    ),
    ChatToolDefinition(
      name: 'read_memory',
      label: '读取记忆',
      description: '按当前问题读取少量相关的个人记忆。',
      group: '读取与检索',
      schema: {
        'type': 'function',
        'function': {
          'name': 'read_memory',
          'description': '按当前问题查询少量相关的用户记忆。',
          'parameters': {
            'type': 'object',
            'properties': {
              'query': {'type': 'string'},
              'projectId': {'type': 'string'},
            },
          },
        },
      },
    ),
    ChatToolDefinition(
      name: 'read_todos',
      label: '读取事项',
      description: '查询今天、全部或指定项目的待办。',
      group: '读取与检索',
      schema: {
        'type': 'function',
        'function': {
          'name': 'read_todos',
          'description': '查询待办事项，默认优先查询今天。',
          'parameters': {
            'type': 'object',
            'properties': {
              'filter': {'type': 'string'},
            },
          },
        },
      },
    ),
    ChatToolDefinition(
      name: 'read_signals',
      label: '分析学习记录',
      description: '查看长期学习行为和习惯变化。',
      group: '读取与检索',
      schema: {
        'type': 'function',
        'function': {
          'name': 'read_signals',
          'description': '查询用户的历史学习行为信号。',
          'parameters': {
            'type': 'object',
            'properties': {
              'type': {'type': 'string'},
              'projectId': {'type': 'string'},
              'range': {'type': 'string'},
              'limit': {'type': 'integer'},
            },
          },
        },
      },
    ),
    ChatToolDefinition(
      name: 'write_todo',
      label: '新建事项',
      description: '根据明确请求创建一条待办事项。',
      group: '创建与执行',
      system: true,
      schema: {
        'type': 'function',
        'function': {
          'name': 'write_todo',
          'description': '创建一个新的待办事项。',
          'parameters': {
            'type': 'object',
            'properties': {
              'title': {'type': 'string'},
              'date': {'type': 'string'},
              'projectId': {'type': 'string'},
              'body': {'type': 'string'},
            },
            'required': ['title'],
          },
        },
      },
    ),
    ChatToolDefinition(
      name: 'move_todo_date',
      label: '移动事项日期',
      description: '将已有待办移动到其他日期，或从日期中移除。',
      group: '创建与执行',
      system: true,
      schema: {
        'type': 'function',
        'function': {
          'name': 'move_todo_date',
          'description':
              '根据待办 id 将其移动到指定日期。date 传 null 或空字符串表示取消日期分配。',
          'parameters': {
            'type': 'object',
            'properties': {
              'todoId': {'type': 'string'},
              'date': {
                'type': 'string',
                'description': '目标日期，格式 YYYY-MM-DD；为空则取消日期',
              },
            },
            'required': ['todoId'],
          },
        },
      },
    ),
    ChatToolDefinition(
      name: 'edit_todo',
      label: '编辑事项',
      description: '修改已有待办的标题或备注。',
      group: '创建与执行',
      system: true,
      schema: {
        'type': 'function',
        'function': {
          'name': 'edit_todo',
          'description': '根据待办 id 修改标题或备注，未提供的字段保持原样。',
          'parameters': {
            'type': 'object',
            'properties': {
              'todoId': {'type': 'string'},
              'title': {'type': 'string'},
              'body': {'type': 'string'},
            },
            'required': ['todoId'],
          },
        },
      },
    ),
    ChatToolDefinition(
      name: 'delete_todo',
      label: '删除事项',
      description: '删除已有待办，执行前需要用户明确确认。',
      group: '创建与执行',
      system: true,
      schema: {
        'type': 'function',
        'function': {
          'name': 'delete_todo',
          'description':
              '根据待办 id 删除待办。必须先向用户说明要删除哪一条，并获得明确同意（confirmed=true）后方可执行。',
          'parameters': {
            'type': 'object',
            'properties': {
              'todoId': {'type': 'string'},
              'confirmed': {
                'type': 'boolean',
                'description': '用户已明确确认删除',
              },
            },
            'required': ['todoId'],
          },
        },
      },
    ),
    ChatToolDefinition(
      name: 'toggle_todo_completion',
      label: '标记完成/未完成',
      description: '将待办标记为完成或未完成，执行前需要用户明确确认。',
      group: '创建与执行',
      system: true,
      schema: {
        'type': 'function',
        'function': {
          'name': 'toggle_todo_completion',
          'description':
              '根据待办 id 设置完成状态。必须先向用户说明要修改哪一条及目标状态，并获得明确同意（confirmed=true）后方可执行。',
          'parameters': {
            'type': 'object',
            'properties': {
              'todoId': {'type': 'string'},
              'completed': {'type': 'boolean'},
              'confirmed': {
                'type': 'boolean',
                'description': '用户已明确确认修改完成状态',
              },
            },
            'required': ['todoId', 'completed'],
          },
        },
      },
    ),
    ChatToolDefinition(
      name: 'create_study_timer',
      label: '计时与闹钟',
      description: '创建学习倒计时或按时间提醒的闹钟卡片。',
      group: '创建与执行',
      schema: {
        'type': 'function',
        'function': {
          'name': 'create_study_timer',
          'description':
              '创建学习计时器或闹钟。相对时长、“开始计时”和“几分钟后提醒”必须使用 timer + minutes；绝对时刻或用户明确说闹钟时才使用 alarm + alertAt。不得把相对时长换算成 alarm。',
          'parameters': {
            'type': 'object',
            'properties': {
              'title': {'type': 'string', 'description': '学习内容，2-32 字'},
              'kind': {
                'type': 'string',
                'enum': ['timer', 'alarm'],
                'description': 'timer 为相对时长倒计时；alarm 仅用于明确的绝对时刻提醒',
              },
              'minutes': {
                'type': 'integer',
                'description': 'timer 时长，1-480 分钟',
              },
              'alertAt': {
                'type': 'string',
                'description': 'alarm 的未来本地时间，ISO 8601 格式',
              },
              'startImmediately': {
                'type': 'boolean',
                'description': '仅用户明确要求现在开始时为 true',
              },
            },
            'required': ['title', 'kind'],
          },
        },
      },
    ),
    ChatToolDefinition(
      name: 'start_project_generation',
      label: '对话新建项目',
      description: '收集完整信息后创建学习项目并进入生成流程。',
      group: '创建与执行',
      schema: {
        'type': 'function',
        'function': {
          'name': 'start_project_generation',
          'description': '只在已获得目标、当前水平、周期和每周投入四项信息后启动项目生成。',
          'parameters': {
            'type': 'object',
            'properties': {
              'goal': {'type': 'string'},
              'level': {'type': 'string'},
              'cycleMonths': {'type': 'integer'},
              'timeConstraint': {'type': 'integer'},
            },
            'required': ['goal', 'level', 'cycleMonths', 'timeConstraint'],
          },
        },
      },
    ),
  ];

  static ChatToolDefinition? byName(String name) {
    for (final definition in definitions) {
      if (definition.name == name) return definition;
    }
    return null;
  }

  static List<Map<String, Object?>> schemasFor(Iterable<String> enabled) {
    final allowed = enabled.toSet();
    return [
      for (final definition in definitions)
        if (allowed.contains(definition.name)) definition.schema,
    ];
  }
}
