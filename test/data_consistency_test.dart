import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sumi/data/chat_database.dart';
import 'package:sumi/data/local_database.dart';
import 'package:sumi/data/signal_database.dart';
import 'package:sumi/models/models.dart';
import 'package:sumi/services/ai_service.dart';
import 'package:sumi/services/daily_planning_policy.dart';
import 'package:sumi/services/secure_settings_store.dart';
import 'package:sumi/services/tool_executor.dart';
import 'package:sumi/services/user_model_service.dart';
import 'package:sumi/services/project_generation.dart';
import 'package:sumi/services/signal_service.dart';
import 'package:sumi/services/snapshot_write_queue.dart';
import 'package:sumi/store/sumi_store.dart';
import 'package:sumi/utils/utils.dart';

class _FakeSecureSettingsStore extends SecureSettingsStore {
  @override
  Future<String> readDeepseekApiKey() async => '';

  @override
  Future<String> readTavilyApiKey() async => '';

  @override
  Future<void> writeDeepseekApiKey(String key) async {}

  @override
  Future<void> writeTavilyApiKey(String key) async {}
}

class _FakeSignalDatabase extends SignalDatabase {
  _FakeSignalDatabase(super.store);

  @override
  Future<List<UserSignal>> query({
    SignalType? type,
    String? projectId,
    String? range,
    int? limit,
  }) async => [];

  @override
  Future<void> clearAll() async {}
}

class _FakeUserModelService extends UserModelService {
  String content;
  String? appendedEntry;
  int writes = 0;
  int backups = 0;

  _FakeUserModelService(super.signalDb, {String? content})
      : content = content ?? '';

  @override
  Future<String> readUserModel() async =>
      content.isEmpty ? defaultUserModel : content;

  @override
  Future<void> writeUserModel(String value) async {
    writes++;
    content = value;
  }

  @override
  Future<void> resetUserModel() async {
    content = defaultUserModel;
    writes++;
  }

  @override
  Future<void> appendToSection(String section, String entry) async {
    appendedEntry = entry;
  }

  @override
  Future<Map<String, String>> computeRealtimeStats() async => {};

  @override
  String injectRealtimeStats(
    String fullContent,
    Map<String, String> stats,
  ) => fullContent;

  @override
  Future<String?> backupUserModel() async {
    backups++;
    return 'backup';
  }
}

class _FailingStatsUserModelService extends _FakeUserModelService {
  _FailingStatsUserModelService(super.signalDb);

  @override
  Future<Map<String, String>> computeRealtimeStats() async {
    throw StateError('stats unavailable');
  }
}

class _InvalidReflectionAi extends AiService {
  _InvalidReflectionAi() : super(apiKey: 'test');

  @override
  Future<WeeklyReflectionResult?> generateWeeklyReflection({
    required String hotPrompt,
    required String warmPrefs,
    required String weeklySignals,
  }) async {
    return const WeeklyReflectionResult(updatedUserModel: '损坏内容');
  }
}

class _CountingLocalDatabase extends SumiLocalDatabase {
  int writes = 0;

  _CountingLocalDatabase(Database database) : super(database: database);

  @override
  Future<void> writeSnapshot(Map<String, Object?> snapshot) async {
    writes++;
    await super.writeSnapshot(snapshot);
  }
}

Future<Database> _openDatabase() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE app_snapshot (
      id TEXT PRIMARY KEY,
      body TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE conversations (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL DEFAULT '',
      date_key TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      pinned INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE messages (
      id TEXT PRIMARY KEY,
      conversation_id TEXT NOT NULL,
      role TEXT NOT NULL,
      content TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      reasoning_content TEXT,
      tool_calls_json TEXT,
      tool_call_id TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE signals (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      signal TEXT NOT NULL,
      time TEXT NOT NULL,
      context_json TEXT NOT NULL DEFAULT '{}',
      project_id TEXT,
      todo_id TEXT,
      domain TEXT,
      created_at TEXT NOT NULL
    )
  ''');
  return db;
}

Future<SumiStore> _createStore(
  Database db, {
  AiTransport? ai,
  UserModelService? userModel,
  SignalDatabase? signals,
  DateTime Function()? now,
}) {
  final local = SumiLocalDatabase(database: db);
  return SumiStore.create(
    database: local,
    secureSettings: _FakeSecureSettingsStore(),
    aiServiceOverride: ai,
    userModelServiceOverride: userModel,
    signalDatabaseOverride: signals,
    now: now,
  );
}

void main() {
  setUpAll(sqfliteFfiInit);

  test('Todo copyWith 可以显式清空可空字段', () {
    final todo = TodoItem(
      id: 'todo',
      source: TodoSource.user,
      projectId: 'project',
      date: '2026-07-15',
      title: '事项',
      body: '备注',
      reminderTime: '09:00',
      createdAt: DateTime(2026),
    );

    final cleared = todo.copyWith(
      projectId: null,
      date: null,
      body: null,
      reminderTime: null,
    );
    expect(cleared.projectId, isNull);
    expect(cleared.date, isNull);
    expect(cleared.body, isNull);
    expect(cleared.reminderTime, isNull);
  });

  test('真实 SignalDatabase 查询返回强类型信号列表', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final signals = SignalDatabase(SumiLocalDatabase(database: db));
    await signals.insert(UserSignal(
      signal: SignalType.todoCreated,
      time: DateTime(2026, 7, 15, 10),
      contextJson: '{"title":"阅读文档"}',
      createdAt: DateTime(2026, 7, 15, 10),
    ));

    final result = await signals.query(range: 'all');

    expect(result, isA<List<UserSignal>>());
    expect(result.single.signal, SignalType.todoCreated);
    expect(result.single.context['title'], '阅读文档');
  });

  test('未完成信号保留 false 并写入真实项目信息', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final signals = SignalDatabase(SumiLocalDatabase(database: db));
    final project = Project(
      id: 'project-1',
      name: '测试项目',
      color: ProjectColor.mint,
      goal: '掌握测试方法',
      createdAt: DateTime.now(),
    );
    final service = SignalService(
      signals,
      projectForId: (id) => id == project.id ? project : null,
    );
    final todo = TodoItem(
      id: 'todo-1',
      source: TodoSource.system,
      projectId: project.id,
      date: dateKey(DateTime.now()),
      title: '执行测试',
      createdAt: DateTime.now(),
    );

    await service.emitTodoUncompleted(todo);
    final signal = (await signals.query(range: 'all')).single;

    expect(signal.context['completedOnTime'], isFalse);
    expect(signal.context['projectName'], '测试项目');
    expect(signal.context['projectGoal'], '掌握测试方法');
    expect(signal.domain, '掌握测试方法');
  });

  test('真实行为统计不会阻断尽管问回复', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final ai = AiService(
      apiKey: 'test',
      client: MockClient(
        (_) async => http.Response(
          'data:${jsonEncode({
            'choices': [
              {
                'delta': {'content': '可以正常回答'},
              },
            ],
          })}\n\ndata:[DONE]\n\n',
          200,
          headers: const {
            'content-type': 'text/event-stream; charset=utf-8',
          },
        ),
      ),
    );
    final local = SumiLocalDatabase(database: db);
    final signals = SignalDatabase(local);
    final store = await _createStore(
      db,
      ai: ai,
      signals: signals,
      userModel: UserModelService(signals),
    );
    final done = Completer<void>();
    store.chatView.addListener(() {
      final view = store.chatView.value;
      final hasReply = view.messages.any(
        (message) => message.role == 'assistant' && message.content.isNotEmpty,
      );
      if ((hasReply || view.failure != null) && !done.isCompleted) {
        done.complete();
      }
    });

    expect(store.sendMessage('尽管问测试'), ChatSendResult.accepted);
    await done.future.timeout(const Duration(seconds: 2));

    expect(store.chatView.value.failure, isNull);
    expect(store.chatView.value.messages.last.content, '可以正常回答');
  });

  test('行为统计失败时聊天降级回答而不是静默停止', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final local = SumiLocalDatabase(database: db);
    final signals = _FakeSignalDatabase(local);
    final ai = AiService(
      apiKey: 'test',
      client: MockClient(
        (_) async => http.Response(
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': '降级后仍可回答'},
              },
            ],
          })}\n\ndata: [DONE]\n\n',
          200,
          headers: const {
            'content-type': 'text/event-stream; charset=utf-8',
          },
        ),
      ),
    );
    final store = await _createStore(
      db,
      ai: ai,
      signals: signals,
      userModel: _FailingStatsUserModelService(signals),
    );
    final done = Completer<void>();
    store.chatView.addListener(() {
      final view = store.chatView.value;
      final hasReply = view.messages.any(
        (message) => message.role == 'assistant' && message.content.isNotEmpty,
      );
      if ((hasReply || view.failure != null) && !done.isCompleted) {
        done.complete();
      }
    });

    store.sendMessage('测试上下文失败');
    await done.future.timeout(const Duration(seconds: 2));

    expect(store.chatView.value.failure, isNull);
    expect(store.chatView.value.messages.last.content, '降级后仍可回答');
  });

  test('聊天请求失败会展示错误且重试不重复用户消息', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    var calls = 0;
    final ai = AiService(
      apiKey: 'test',
      client: MockClient((_) async {
        calls++;
        if (calls == 1) return http.Response('unauthorized', 401);
        return http.Response(
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': '重试成功'},
              },
            ],
          })}\n\ndata: [DONE]\n\n',
          200,
          headers: const {
            'content-type': 'text/event-stream; charset=utf-8',
          },
        );
      }),
    );
    final local = SumiLocalDatabase(database: db);
    final signals = _FakeSignalDatabase(local);
    final store = await _createStore(
      db,
      ai: ai,
      signals: signals,
      userModel: _FakeUserModelService(signals),
    );
    final failed = Completer<void>();
    store.chatView.addListener(() {
      if (store.chatView.value.failure != null && !failed.isCompleted) {
        failed.complete();
      }
    });

    store.sendMessage('请回答');
    await failed.future.timeout(const Duration(seconds: 2));
    expect(store.chatView.value.failure?.retryable, isTrue);

    final retried = Completer<void>();
    store.chatView.addListener(() {
      final hasReply = store.chatView.value.messages.any(
        (message) => message.role == 'assistant' && message.content == '重试成功',
      );
      if (hasReply && !retried.isCompleted) retried.complete();
    });
    await store.retryLastFailedMessage();
    await retried.future.timeout(const Duration(seconds: 2));

    expect(
      store.chatView.value.messages.where((message) => message.role == 'user'),
      hasLength(1),
    );
    expect(store.chatView.value.failure, isNull);
  });

  test('AI 工具未指定项目时创建用户事项', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    var calls = 0;
    final ai = AiService(
      apiKey: 'test',
      client: MockClient((_) async {
        calls++;
        final delta = calls == 1
            ? {
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'call-1',
                    'function': {
                      'name': 'write_todo',
                      'arguments': '{"title":"整理桌面"}',
                    },
                  },
                ],
              }
            : {'content': '已经创建'};
        return http.Response(
          'data: ${jsonEncode({
            'choices': [
              {'delta': delta},
            ],
          })}\n\ndata: [DONE]\n\n',
          200,
          headers: const {
            'content-type': 'text/event-stream; charset=utf-8',
          },
        );
      }),
    );
    final local = SumiLocalDatabase(database: db);
    final signals = _FakeSignalDatabase(local);
    final store = await _createStore(
      db,
      ai: ai,
      signals: signals,
      userModel: _FakeUserModelService(signals),
    );
    final done = Completer<void>();
    store.chatView.addListener(() {
      final hasReply = store.chatView.value.messages.any(
        (message) => message.role == 'assistant' && message.content == '已经创建',
      );
      if (hasReply && !done.isCompleted) done.complete();
    });

    store.sendMessage('帮我创建事项');
    await done.future.timeout(const Duration(seconds: 2));

    final todo = store.todoItems.singleWhere((item) => item.title == '整理桌面');
    expect(todo.source, TodoSource.user);
    expect(todo.projectId, isNull);
  });

  test('记忆替换写入新内容并保留置信度，追加不产生双横线', () async {
    final signalDb = _FakeSignalDatabase(SumiLocalDatabase());
    final userModel = _FakeUserModelService(signalDb);
    final result = userModel.mergeMemoryEntry(
      '用户喜欢早上练习英语',
      '- [确信] 用户喜欢早上学习英语',
    );
    expect(result.action, 'replace');
    expect(result.mergedCoreMemory, contains('- [确信] 用户喜欢早上练习英语'));

    final executor = ToolExecutor(
      userModelService: userModel,
      signalDatabase: signalDb,
      readTodos: ({filter}) => '',
      writeTodo: ({required title, date, projectId, body}) async {},
    );
    await executor.execute(
      const ToolCall(
        id: 'call',
        name: 'write_memory',
        arguments: {'content': '用户偏好短时练习', 'confidence': '推断'},
      ),
    );
    expect(userModel.appendedEntry, '[推断] 用户偏好短时练习');
  });

  test('清空数据后写回完整用户模型模板', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final local = SumiLocalDatabase(database: db);
    final signals = _FakeSignalDatabase(local);
    final userModel = _FakeUserModelService(signals);
    final store = await _createStore(
      db,
      signals: signals,
      userModel: userModel,
    );

    await store.clearAllData();
    expect(userModel.isValidUserModel(userModel.content), isTrue);
  });

  test('损坏的周度反思不覆盖模型也不更新时间', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final local = SumiLocalDatabase(database: db);
    final signals = _FakeSignalDatabase(local);
    final userModel = _FakeUserModelService(signals);
    final store = await _createStore(
      db,
      ai: _InvalidReflectionAi(),
      signals: signals,
      userModel: userModel,
      now: () => DateTime(2026, 7, 19, 10),
    );
    final writesBefore = userModel.writes;

    await store.checkAndRunWeeklyReflection();
    expect(store.lastWeeklyReflection, isNull);
    expect(userModel.writes, writesBefore);
    expect(userModel.backups, 0);
  });

  test('重新生成只清理最后一轮工具结果', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final chat = ChatDatabase(SumiLocalDatabase(database: db));
    await db.insert('conversations', {
      'id': 'conv',
      'title': '',
      'date_key': '2026-07-15',
      'created_at': '2026-07-15T09:00:00',
      'updated_at': '2026-07-15T09:00:00',
      'pinned': 0,
    });
    for (final row in [
      ['assistant-old', 'assistant', '2026-07-15T09:00:00'],
      ['tool-old', 'tool', '2026-07-15T09:00:01'],
      ['assistant-last', 'assistant', '2026-07-15T10:00:00'],
      ['tool-last', 'tool', '2026-07-15T10:00:01'],
    ]) {
      await db.insert('messages', {
        'id': row[0],
        'conversation_id': 'conv',
        'role': row[1],
        'content': '',
        'created_at': row[2],
      });
    }

    await chat.popToolMessagesAfter('conv', 'assistant-last');
    await chat.popLastAssistantMessage('conv');
    final rows = await db.query('messages', orderBy: 'created_at');
    expect(rows.map((row) => row['id']), ['assistant-old', 'tool-old']);
  });

  test('每日规划只统计本周并能选择跨月后的新月卡', () {
    final todos = [
      for (final date in ['2026-07-12', '2026-07-13', '2026-07-19', '2026-07-20'])
        TodoItem(
          id: date,
          source: TodoSource.system,
          projectId: 'project',
          date: date,
          title: date,
          createdAt: DateTime(2026),
        ),
    ];
    final count = DailyPlanningPolicy.scheduledCountForWeek(
      todos: todos,
      projectId: 'project',
      today: DateTime(2026, 7, 15),
    );
    expect(count, 2);

    final cards = [
      const MonthCard(id: 'old', projectId: 'project', monthIndex: 0, title: '旧月'),
      const MonthCard(id: 'new', projectId: 'project', monthIndex: 1, title: '新月'),
    ];
    expect(
      DailyPlanningPolicy.cardForMonth(
        cards: cards,
        projectId: 'project',
        monthIndex: 1,
      )?.id,
      'new',
    );
  });

  test('流式片段只通知聊天视图，不广播全局 Store', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final sse = StringBuffer();
    for (var i = 0; i < 100; i++) {
      sse.writeln(
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': '字'},
            },
          ],
        })}',
      );
      sse.writeln();
    }
    sse.writeln('data: [DONE]');
    final ai = AiService(
      apiKey: 'test',
      client: MockClient(
        (_) async => http.Response(
          sse.toString(),
          200,
          headers: const {'content-type': 'text/event-stream; charset=utf-8'},
        ),
      ),
    );
    final local = SumiLocalDatabase(database: db);
    final signals = _FakeSignalDatabase(local);
    final userModel = _FakeUserModelService(signals);
    final store = await _createStore(
      db,
      ai: ai,
      signals: signals,
      userModel: userModel,
    );
    var nonChatNotifications = 0;
    var chatNotifications = 0;
    final done = Completer<void>();
    store.todoController.addListener(() => nonChatNotifications++);
    store.projectController.addListener(() => nonChatNotifications++);
    store.settingsController.addListener(() => nonChatNotifications++);
    store.chatView.addListener(() {
      chatNotifications++;
      if (!store.chatView.value.isStreaming && !done.isCompleted) {
        done.complete();
      }
    });

    expect(store.sendMessage('测试'), ChatSendResult.accepted);
    await done.future.timeout(const Duration(seconds: 2));
    expect(nonChatNotifications, 0);
    expect(chatNotifications, lessThan(10));
    expect(store.chatView.value.messages.last.content.length, 100);
  });

  test('旧版 v2 快照无需迁移即可装载到分域控制器', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final local = SumiLocalDatabase(database: db);
    await local.writeSnapshot({
      'v': 2,
      'settings': const AppSettings(userName: '测试用户').toJson(),
      'projects': [
        Project(
          id: 'project',
          name: '项目',
          color: ProjectColor.lemon,
          createdAt: DateTime(2026),
        ).toJson(),
      ],
      'monthCards': <Object?>[],
      'todos': [
        TodoItem(
          id: 'todo',
          source: TodoSource.user,
          title: '旧事项',
          createdAt: DateTime(2026),
        ).toJson(),
      ],
      'selectedDate': '2026-07-15T00:00:00.000',
    });

    final store = await SumiStore.create(
      database: local,
      secureSettings: _FakeSecureSettingsStore(),
    );
    expect(store.todoController.items.single.title, '旧事项');
    expect(store.projectController.projects.single.id, 'project');
    expect(store.settingsController.value.userName, '测试用户');
    expect(store.selectedDate, DateTime(2026, 7, 15));
  });

  test('分域通知互不串扰，项目级联只影响项目和事项域', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final store = await _createStore(db);
    var todoEvents = 0;
    var projectEvents = 0;
    var settingsEvents = 0;
    store.todoController.addListener(() => todoEvents++);
    store.projectController.addListener(() => projectEvents++);
    store.settingsController.addListener(() => settingsEvents++);

    await store.addUserTodo('独立事项');
    expect((todoEvents, projectEvents, settingsEvents), (1, 0, 0));

    const projectId = 'project-notification';
    store.restoreFromMap({
      'projects': [
        Project(
          id: projectId,
          name: '项目',
          color: ProjectColor.mint,
          createdAt: DateTime(2026),
        ).toJson(),
      ],
    });
    await store.addSystemTodo('系统事项', projectId);
    final beforeDelete = (todoEvents, projectEvents, settingsEvents);
    store.deleteProject(projectId);
    expect(todoEvents, beforeDelete.$1 + 1);
    expect(projectEvents, beforeDelete.$2 + 1);
    expect(settingsEvents, beforeDelete.$3);
    expect(
      store.todoItems.where((todo) => todo.projectId == projectId),
      isEmpty,
    );
    await store.writeToDb();
  });

  test('API Key 更新会原子替换 AiRuntime 且只通知设置域', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final store = await _createStore(db);
    var settingsEvents = 0;
    var todoEvents = 0;
    store.settingsController.addListener(() => settingsEvents++);
    store.todoController.addListener(() => todoEvents++);

    await store.updateDeepseekApiKey('key-1');
    final first = store.aiRuntime;
    await store.updateDeepseekApiKey('key-2');
    expect(first, isNotNull);
    expect(store.aiRuntime, isNot(same(first)));
    expect(settingsEvents, 2);
    expect(todoEvents, 0);
    await store.writeToDb();
  });

  test('单次事项操作只安排一次快照持久化', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final local = _CountingLocalDatabase(db);
    final store = await SumiStore.create(
      database: local,
      secureSettings: _FakeSecureSettingsStore(),
    );
    final before = local.writes;
    await store.addUserTodo('只写一次');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(local.writes, before + 1);
  });

  test('快照队列在写入繁忙时只保留最新状态', () async {
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final written = <int>[];
    final queue = SnapshotWriteQueue((snapshot) async {
      written.add(snapshot['version']! as int);
      if (written.length == 1) {
        firstStarted.complete();
        await releaseFirst.future;
      }
    });

    queue.schedule({'version': 0});
    await firstStarted.future;
    for (var i = 1; i <= 100; i++) {
      queue.schedule({'version': i});
    }
    releaseFirst.complete();
    await queue.flush();

    expect(written, [0, 100]);
  });

  test('项目计划一次提交项目、月卡、事项和快照', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final local = _CountingLocalDatabase(db);
    final store = await SumiStore.create(
      database: local,
      secureSettings: _FakeSecureSettingsStore(),
    );
    final before = local.writes;
    final today = dateKey(DateTime.now());
    const request = ProjectGenerationRequest(
      projectId: 'project-generated',
      goal: '学习自动化测试',
      level: '零基础',
      cycleMonths: 1,
      timeConstraint: 6,
      color: ProjectColor.mint,
    );
    const assessment = GoalAssessment(
      clarity: 0.8,
      feasibility: 0.8,
      challengeFit: 0.7,
      decomposability: 0.8,
      timeRealism: 0.7,
      motivationPotential: 0.7,
      resourceAccess: 0.9,
      measurability: 0.8,
      verdict: AssessmentVerdict.a,
      goalSummary: '自动化测试',
    );
    final plan = PlanResult(
      projectTitle: '计划凝练标题',
      monthPlans: const [
        MonthPlanItem(
          monthIndex: 0,
          title: '基础阶段',
          summary: '建立测试基础并完成练习',
        ),
      ],
      todayTodos: [TodoSeed(title: '阅读测试资料', date: today)],
    );

    await store.commitProjectPlan(request, assessment, plan);
    await store.flushPersistence();

    expect(store.projectList.single.name, '自动化测试');
    expect(store.monthCardList, hasLength(1));
    expect(store.todoItems.single.projectId, 'project-generated');
    expect(local.writes, before + 1);
    expect(
      () => store.todoController.items.add(store.todoItems.single),
      throwsUnsupportedError,
    );
  });

  test('跳过评估时使用规划返回的凝练项目标题', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final store = await _createStore(db);
    final today = dateKey(DateTime.now());
    const request = ProjectGenerationRequest(
      projectId: 'project-title',
      goal: '这是一个非常长并且不适合直接显示在卡片上的学习目标描述',
      level: '零基础',
      cycleMonths: 1,
      timeConstraint: 6,
      color: ProjectColor.sky,
    );
    final plan = PlanResult(
      projectTitle: '自动化测试入门',
      monthPlans: const [
        MonthPlanItem(
          monthIndex: 0,
          title: '基础阶段',
          summary: '建立基础',
        ),
      ],
      todayTodos: [TodoSeed(title: '阅读资料', date: today)],
    );

    await store.commitProjectPlan(request, null, plan);

    expect(store.projectList.single.name, '自动化测试入门');
    expect(store.projectList.single.goalSummary, '自动化测试入门');
  });
}
