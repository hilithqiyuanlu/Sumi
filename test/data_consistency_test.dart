import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sumi/data/chat_database.dart';
import 'package:sumi/data/local_database.dart';
import 'package:sumi/data/signal_database.dart';
import 'package:sumi/features/calendar/month_view_sheet.dart';
import 'package:sumi/models/models.dart';
import 'package:sumi/services/ai_service.dart';
import 'package:sumi/services/daily_planning_policy.dart';
import 'package:sumi/services/secure_settings_store.dart';
import 'package:sumi/services/user_model_service.dart';
import 'package:sumi/services/memory_service.dart';
import 'package:sumi/services/memory_extraction.dart';
import 'package:sumi/services/project_generation.dart';
import 'package:sumi/services/signal_service.dart';
import 'package:sumi/services/snapshot_write_queue.dart';
import 'package:sumi/sumi_scope.dart';
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

class _DelayedStreamClient extends http.BaseClient {
  final _chunks = StreamController<List<int>>();
  final requested = Completer<void>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!requested.isCompleted) requested.complete();
    return http.StreamedResponse(
      _chunks.stream,
      200,
      headers: const {'content-type': 'text/event-stream; charset=utf-8'},
    );
  }

  Future<void> completeWithReply(String reply) async {
    _chunks.add(
      utf8.encode(
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': reply},
            },
          ],
        })}\n\ndata: [DONE]\n\n',
      ),
    );
    await _chunks.close();
  }
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
  String injectRealtimeStats(String fullContent, Map<String, String> stats) =>
      fullContent;

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
      tool_call_id TEXT,
      todo_result_json TEXT
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
  await db.execute('''
    CREATE TABLE milestones (
      id TEXT PRIMARY KEY, project_id TEXT NOT NULL, todo_id TEXT NOT NULL,
      source_message_id TEXT NOT NULL, quote TEXT NOT NULL, todo_title TEXT NOT NULL,
      month_index INTEGER NOT NULL, occurred_at TEXT NOT NULL, memory_id TEXT,
      created_at TEXT NOT NULL, UNIQUE(source_message_id, todo_id)
    )
  ''');
  await db.execute('''
    CREATE TABLE pending_milestone_statements (
      message_id TEXT NOT NULL, todo_id TEXT NOT NULL, quote TEXT NOT NULL,
      occurred_at TEXT NOT NULL, created_at TEXT NOT NULL,
      UNIQUE(message_id, todo_id)
    )
  ''');
  await db.execute('''
    CREATE TABLE user_hypotheses (
      id TEXT PRIMARY KEY, kind TEXT NOT NULL, scope TEXT NOT NULL DEFAULT 'global',
      claim_json TEXT NOT NULL, confidence REAL NOT NULL, support_count INTEGER NOT NULL DEFAULT 0,
      contradict_count INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL, source TEXT NOT NULL,
      last_verified_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE recommendation_events (
      id TEXT PRIMARY KEY, text TEXT NOT NULL, topic TEXT NOT NULL, hypothesis_id TEXT,
      shown_at TEXT NOT NULL, selected_at TEXT, feedback_at TEXT, feedback_type TEXT,
      context_json TEXT NOT NULL DEFAULT '{}'
    )
  ''');
  await db.execute('''
    CREATE TABLE schedule_recommendation_events (
      id TEXT PRIMARY KEY, todo_id TEXT NOT NULL UNIQUE, original_date TEXT NOT NULL,
      suggested_date TEXT NOT NULL, hypothesis_id TEXT NOT NULL, shown_at TEXT NOT NULL,
      accepted_at TEXT, context_json TEXT NOT NULL DEFAULT '{}'
    )
  ''');
  await db.execute('''
    CREATE TABLE study_timers (
      id TEXT PRIMARY KEY,
      tool_call_id TEXT NOT NULL,
      conversation_id TEXT NOT NULL,
      title TEXT NOT NULL,
      kind TEXT NOT NULL DEFAULT 'timer',
      total_seconds INTEGER NOT NULL,
      remaining_seconds INTEGER NOT NULL,
      status TEXT NOT NULL,
      started_at TEXT,
      alert_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
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
    await signals.insert(
      UserSignal(
        signal: SignalType.todoCreated,
        time: DateTime(2026, 7, 15, 10),
        contextJson: '{"title":"阅读文档"}',
        createdAt: DateTime(2026, 7, 15, 10),
      ),
    );

    final result = await signals.query(range: 'all');

    expect(result, isA<List<UserSignal>>());
    expect(result.single.signal, SignalType.todoCreated);
    expect(result.single.context['title'], '阅读文档');
  });

  test('建议选择形成可追溯隐式记忆，两次反馈后可用于 Agent', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final service = MemoryService(SumiLocalDatabase(database: db));
    final stats = <String, String>{
      'weeklyCompletionRate': '80%',
      'planDeviationRate': '0%',
    };

    final first = (await service.createSuggestions(
      realtimeStats: stats,
    )).firstWhere((item) => item.topic == 'plan');
    await service.recordSelected(first);
    expect(await service.hotForAgent('制定计划'), isEmpty);

    final second = (await service.createSuggestions(
      realtimeStats: stats,
    )).firstWhere((item) => item.topic == 'plan');
    await service.recordSelected(second);
    final trusted = await service.hotForAgent('制定计划');
    expect(trusted.single.content, 'plan');
    expect(trusted.single.confidence, greaterThanOrEqualTo(0.70));
  });

  test('不再推荐会停用默认类别，且不会再次生成', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final service = MemoryService(SumiLocalDatabase(database: db));
    final stats = <String, String>{
      'weeklyCompletionRate': '80%',
      'planDeviationRate': '0%',
    };
    final suggestion = (await service.createSuggestions(
      realtimeStats: stats,
    )).firstWhere((item) => item.topic == 'plan');
    await service.recordFeedback(suggestion, disableTopic: true);
    final later = await service.createSuggestions(realtimeStats: stats);
    expect(later.where((item) => item.topic == 'plan'), isEmpty);
    expect((await service.list()).single.status, MemoryStatus.disabled);
  });

  test('旧版首页建议偏好会迁移为记忆并关联原事件', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    await db.insert('user_hypotheses', {
      'id': 'legacy-plan',
      'kind': 'suggestionTopic',
      'scope': 'global',
      'claim_json': '{"topic":"plan"}',
      'confidence': .78,
      'support_count': 3,
      'contradict_count': 0,
      'status': 'active',
      'source': 'interaction',
      'created_at': '2026-07-15T09:00:00',
      'updated_at': '2026-07-15T09:00:00',
    });
    await db.insert('recommendation_events', {
      'id': 'legacy-event',
      'text': '帮我制定今天的学习计划',
      'topic': 'plan',
      'shown_at': '2026-07-15T09:00:00',
      'context_json': '{}',
    });
    final service = MemoryService(SumiLocalDatabase(database: db));
    await service.importLegacyHypotheses();

    final memory = (await service.list()).single;
    final events = await db.query(
      'recommendation_events',
      where: 'id = ?',
      whereArgs: ['legacy-event'],
    );
    expect(memory.type, MemoryType.implicit);
    expect(memory.content, 'plan');
    expect(events.single['memory_id'], memory.id);
    final legacyTables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'user_hypotheses'",
    );
    expect(legacyTables, isEmpty);
  });

  test('信号记录待办来源', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final signals = SignalDatabase(SumiLocalDatabase(database: db));
    final service = SignalService(signals);
    final user = TodoItem(
      id: 'user',
      source: TodoSource.user,
      date: dateKey(DateTime.now()),
      title: '手动事项',
      createdAt: DateTime.now(),
    );
    final system = TodoItem(
      id: 'system',
      source: TodoSource.system,
      date: dateKey(DateTime.now()),
      title: '系统事项',
      createdAt: DateTime.now(),
    );
    await service.emitTodoCreated(user);
    await service.emitTodoCreated(system);
    final records = await signals.query(range: 'all', limit: 10);
    expect(
      records.firstWhere((s) => s.todoId == 'user').context['source'],
      'user',
    );
    expect(
      records.firstWhere((s) => s.todoId == 'system').context['source'],
      'system',
    );
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
          headers: const {'content-type': 'text/event-stream; charset=utf-8'},
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

  test('只能编辑最新用户消息，编辑后从该消息重新发送', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final ai = AiService(
      apiKey: 'test',
      client: MockClient(
        (_) async => http.Response(
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': '编辑后的回复'},
              },
            ],
          })}\n\ndata: [DONE]\n\n',
          200,
          headers: const {'content-type': 'text/event-stream; charset=utf-8'},
        ),
      ),
    );
    final store = await _createStore(db, ai: ai);
    await store.selectDate(DateTime.now());
    final conversationId = store.currentConversationId!;
    final chat = store.chatDatabase!;
    final now = DateTime.now().subtract(const Duration(seconds: 10));
    final existing = [
      ChatMessage(
        id: 'user-1',
        conversationId: conversationId,
        role: 'user',
        content: '第一条',
        createdAt: now,
      ),
      ChatMessage(
        id: 'assistant-1',
        conversationId: conversationId,
        role: 'assistant',
        content: '第一条回复',
        createdAt: now.add(const Duration(seconds: 1)),
      ),
      ChatMessage(
        id: 'user-2',
        conversationId: conversationId,
        role: 'user',
        content: '需要修改的内容',
        createdAt: now.add(const Duration(seconds: 2)),
      ),
      ChatMessage(
        id: 'assistant-2',
        conversationId: conversationId,
        role: 'assistant',
        content: '旧回复',
        createdAt: now.add(const Duration(seconds: 3)),
      ),
    ];
    for (final message in existing) {
      await chat.saveMessage(message);
    }
    await store.selectDate(DateTime.now().subtract(const Duration(days: 1)));
    await store.selectDate(DateTime.now());

    expect(
      await store.editAndResendMessage(0, '不应编辑旧消息'),
      ChatSendResult.empty,
    );
    expect(store.currentMessages, hasLength(4));

    final completed = Completer<void>();
    store.chatView.addListener(() {
      final messages = store.chatView.value.messages;
      if (messages.isNotEmpty &&
          !store.chatView.value.isStreaming &&
          messages.last.content == '编辑后的回复' &&
          !completed.isCompleted) {
        completed.complete();
      }
    });
    expect(
      await store.editAndResendMessage(2, '修改后的内容'),
      ChatSendResult.accepted,
    );
    await completed.future.timeout(const Duration(seconds: 2));

    expect(store.currentMessages.map((message) => message.content), [
      '第一条',
      '第一条回复',
      '修改后的内容',
      '编辑后的回复',
    ]);
    expect(
      (await chat.loadMessages(
        conversationId,
      )).map((message) => message.content),
      ['第一条', '第一条回复', '修改后的内容', '编辑后的回复'],
    );
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
          headers: const {'content-type': 'text/event-stream; charset=utf-8'},
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
          headers: const {'content-type': 'text/event-stream; charset=utf-8'},
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
          headers: const {'content-type': 'text/event-stream; charset=utf-8'},
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

  test('提取记忆必须引用当前用户原话，且支持显式替代', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final local = SumiLocalDatabase(database: db);
    final memory = MemoryService(local);
    await memory.claimExtraction('message-1');
    final saved = await memory.applyExtractionDecision(
      messageId: 'message-1',
      userMessage: '我明确偏好短时练习。',
      decision: const MemoryExtractionDecision(
        action: MemoryExtractionAction.save,
        category: 'preference',
        content: '偏好短时练习',
        quotedText: '我明确偏好短时练习',
      ),
      candidateReplaceIds: const {},
    );
    expect(saved, isTrue);
    final old = (await memory.list()).single;
    await memory.claimExtraction('message-2');
    final replaced = await memory.applyExtractionDecision(
      messageId: 'message-2',
      userMessage: '之前的偏好不对，现在我更喜欢长时间专注。',
      decision: MemoryExtractionDecision(
        action: MemoryExtractionAction.replace,
        category: 'preference',
        content: '偏好长时间专注',
        quotedText: '现在我更喜欢长时间专注',
        replacesId: old.id,
      ),
      candidateReplaceIds: {old.id},
    );
    expect(replaced, isTrue);
    expect(
      (await memory.list())
          .where((item) => item.status == MemoryStatus.active)
          .single
          .content,
      '偏好长时间专注',
    );
    expect(
      (await memory.list()).firstWhere((item) => item.id == old.id).status,
      MemoryStatus.superseded,
    );
  });

  test('提取运行只处理一次，重复明确记忆只追加证据', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final memory = MemoryService(SumiLocalDatabase(database: db));
    const decision = MemoryExtractionDecision(
      action: MemoryExtractionAction.save,
      category: 'constraint',
      content: '晚上不安排任务',
      quotedText: '以后晚上不要安排任务',
    );

    expect(await memory.claimExtraction('message-1'), isTrue);
    expect(await memory.claimExtraction('message-1'), isFalse);
    expect(
      await memory.applyExtractionDecision(
        messageId: 'message-1',
        userMessage: '以后晚上不要安排任务。',
        decision: decision,
        candidateReplaceIds: const {},
      ),
      isTrue,
    );
    expect(await memory.claimExtraction('message-2'), isTrue);
    expect(
      await memory.applyExtractionDecision(
        messageId: 'message-2',
        userMessage: '以后晚上不要安排任务。',
        decision: decision,
        candidateReplaceIds: const {},
      ),
      isTrue,
    );
    final items = await memory.list();
    expect(items, hasLength(1));
    expect(await memory.evidenceFor(items.single.id), hasLength(2));

    expect(await memory.claimExtraction('message-3'), isTrue);
    expect(
      await memory.applyExtractionDecision(
        messageId: 'message-3',
        userMessage: '今晚有空。',
        decision: decision,
        candidateReplaceIds: const {},
      ),
      isFalse,
    );
    expect(await memory.list(), hasLength(1));
  });

  test('记忆采集诊断只返回状态聚合与失败类别', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final memory = MemoryService(
      SumiLocalDatabase(database: db),
      now: () => DateTime(2026, 7, 16, 10),
    );

    await memory.claimExtraction('ignored');
    await memory.applyExtractionDecision(
      messageId: 'ignored',
      userMessage: '今天随便聊聊。',
      decision: const MemoryExtractionDecision(
        action: MemoryExtractionAction.ignore,
      ),
      candidateReplaceIds: const {},
    );
    await memory.claimExtraction('saved');
    await memory.applyExtractionDecision(
      messageId: 'saved',
      userMessage: '我通常更适合短时练习。',
      decision: const MemoryExtractionDecision(
        action: MemoryExtractionAction.save,
        category: 'preference',
        content: '偏好短时练习',
        quotedText: '我通常更适合短时练习',
      ),
      candidateReplaceIds: const {},
    );
    await memory.claimExtraction('failed');
    await memory.applyExtractionDecision(
      messageId: 'failed',
      userMessage: '我通常更适合短时练习。',
      decision: const MemoryExtractionDecision(
        action: MemoryExtractionAction.save,
        category: 'preference',
        content: '偏好短时练习',
        quotedText: '不存在的原话',
      ),
      candidateReplaceIds: const {},
    );

    final diagnostics = await memory.extractionDiagnostics();

    expect(
      (diagnostics.applied, diagnostics.ignored, diagnostics.failed),
      (1, 1, 1),
    );
    expect(diagnostics.failuresByCategory, {'validation': 1});
  });

  test('旧记忆采集表会自动补充失败类别列', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    await db.execute('''CREATE TABLE memory_extraction_runs (
      message_id TEXT PRIMARY KEY, status TEXT NOT NULL,
      decision_json TEXT, processed_at TEXT NOT NULL)''');
    final memory = MemoryService(SumiLocalDatabase(database: db));

    await memory.ensureTables();
    await memory.claimExtraction('legacy-run');
    await memory.finishExtraction(
      'legacy-run',
      status: 'failed',
      errorCategory: 'runtime',
    );

    final columns = await db.rawQuery(
      'PRAGMA table_info(memory_extraction_runs)',
    );
    expect(columns.any((column) => column['name'] == 'error_category'), isTrue);
    expect((await memory.extractionDiagnostics()).failuresByCategory, {
      'runtime': 1,
    });
  });

  test('当前学习状态会按项目和类别替换，并在 30 天后过期', () async {
    var now = DateTime(2026, 7, 1, 9);
    final db = await _openDatabase();
    addTearDown(db.close);
    final memory = MemoryService(
      SumiLocalDatabase(database: db),
      now: () => now,
    );
    await memory.ensureTables();
    await memory.claimExtraction('progress-1');
    final first = await memory.applyExtractionDecision(
      messageId: 'progress-1',
      userMessage: '我现在学到第三章了。',
      decision: const MemoryExtractionDecision(
        action: MemoryExtractionAction.save,
        type: MemoryType.current,
        category: 'progress',
        content: '学到第三章',
        quotedText: '我现在学到第三章了',
      ),
      candidateReplaceIds: const {},
      currentProjectId: 'project-1',
    );
    expect(first, isTrue);

    await memory.claimExtraction('progress-2');
    final second = await memory.applyExtractionDecision(
      messageId: 'progress-2',
      userMessage: '我已经学到第五章了。',
      decision: const MemoryExtractionDecision(
        action: MemoryExtractionAction.save,
        type: MemoryType.current,
        category: 'progress',
        content: '学到第五章',
        quotedText: '我已经学到第五章了',
      ),
      candidateReplaceIds: const {},
      currentProjectId: 'project-1',
    );
    expect(second, isTrue);
    var current = (await memory.list())
        .where((item) => item.type == MemoryType.current)
        .toList();
    expect(
      current
          .where((item) => item.status == MemoryStatus.active)
          .single
          .content,
      '学到第五章',
    );

    now = now.add(const Duration(days: 31));
    await memory.expireStaleCurrent();
    current = (await memory.list())
        .where((item) => item.type == MemoryType.current)
        .toList();
    expect(current.every((item) => item.status != MemoryStatus.active), isTrue);
  });

  test('记忆召回优先明确约束，且不混入其他项目的当前事项', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final memory = MemoryService(SumiLocalDatabase(database: db));
    final constraint = await memory.addManual(
      type: MemoryType.explicit,
      category: 'constraint',
      content: '晚上不安排任务',
    );
    final preference = await memory.addManual(
      type: MemoryType.explicit,
      category: 'preference',
      content: '喜欢复盘学习进度',
    );
    final projectCurrent = await memory.addManual(
      type: MemoryType.current,
      category: 'focus',
      content: '准备日语考试',
      projectId: 'project-a',
    );
    final otherProject = await memory.addManual(
      type: MemoryType.current,
      category: 'focus',
      content: '复习数学竞赛',
      projectId: 'project-b',
    );

    final result = await memory.hotForAgent(
      '今晚怎么安排学习',
      projectId: 'project-a',
      semanticScores: {
        constraint.id: .82,
        preference.id: .98,
        otherProject.id: .99,
      },
    );
    expect(result.first.id, constraint.id);
    expect(result.any((item) => item.id == projectCurrent.id), isTrue);
    expect(result.any((item) => item.id == otherProject.id), isFalse);
  });

  test('清空数据后清除结构化记忆', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final local = SumiLocalDatabase(database: db);
    final signals = _FakeSignalDatabase(local);
    final store = await _createStore(db, signals: signals);

    await store.clearAllData();
    expect(await store.memoryService?.list(), isEmpty);
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
      for (final date in [
        '2026-07-12',
        '2026-07-13',
        '2026-07-19',
        '2026-07-20',
      ])
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
      const MonthCard(
        id: 'old',
        projectId: 'project',
        monthIndex: 0,
        title: '旧月',
      ),
      const MonthCard(
        id: 'new',
        projectId: 'project',
        monthIndex: 1,
        title: '新月',
      ),
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

  test('切换会话时流式回复不会覆盖当前用户消息', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final local = SumiLocalDatabase(database: db);
    final chatDb = ChatDatabase(local);
    final yesterday = dateOnly(
      DateTime.now().subtract(const Duration(days: 1)),
    );
    final previousConversation = await chatDb.createConversationForDate(
      dateKey(yesterday),
    );
    await chatDb.saveMessage(
      ChatMessage(
        id: 'previous-user-message',
        conversationId: previousConversation.id,
        role: 'user',
        content: '昨天的问题',
        createdAt: yesterday,
      ),
    );

    final client = _DelayedStreamClient();
    final signals = _FakeSignalDatabase(local);
    final store = await _createStore(
      db,
      ai: AiService(apiKey: 'test', client: client),
      signals: signals,
      userModel: _FakeUserModelService(signals),
    );
    final today = dateOnly(DateTime.now());

    expect(store.sendMessage('今天的问题'), ChatSendResult.accepted);
    await client.requested.future.timeout(const Duration(seconds: 2));

    await store.selectDate(yesterday);
    expect(store.chatView.value.isStreaming, isFalse);
    expect(store.chatView.value.messages, hasLength(1));
    expect(store.chatView.value.messages.single.content, '昨天的问题');

    await client.completeWithReply('原会话的回复');
    await Future<void>.delayed(Duration.zero);

    expect(store.chatView.value.messages.single.content, '昨天的问题');
    await store.selectDate(today);
    expect(store.chatView.value.messages.map((message) => message.content), [
      '今天的问题',
      '原会话的回复',
    ]);
  });

  test('日期会话互不混合，未来日期保持临时且不落库', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final local = SumiLocalDatabase(database: db);
    final chatDb = ChatDatabase(local);
    final today = dateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    final first = await chatDb.createConversationForDate(dateKey(yesterday));
    final second = await chatDb.createConversationForDate(dateKey(today));
    await chatDb.saveMessage(
      ChatMessage(
        id: 'yesterday-message',
        conversationId: first.id,
        role: 'user',
        content: '昨天的对话',
        createdAt: yesterday,
      ),
    );
    await chatDb.saveMessage(
      ChatMessage(
        id: 'today-message',
        conversationId: second.id,
        role: 'user',
        content: '今天的对话',
        createdAt: today,
      ),
    );
    final store = await _createStore(db);

    await store.selectDate(yesterday);
    expect(store.chatView.value.messages.single.content, '昨天的对话');

    await store.selectDate(today);
    expect(store.chatView.value.messages.single.content, '今天的对话');

    final tomorrow = today.add(const Duration(days: 1));
    await store.selectDate(tomorrow);
    expect(store.chatView.value.isTemporaryConversation, isTrue);
    expect(await chatDb.findConversationByDate(dateKey(tomorrow)), isNull);
  });

  test('完成待办记录完成时间，取消完成时清除', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final store = await _createStore(db);
    final todo = await store.addUserTodo('完成排序测试');
    expect(todo, isNotNull);

    await store.toggleTodo(todo!.id);
    final completed = store.todoItems.single;
    expect(completed.done, isTrue);
    expect(completed.completedAt, isNotNull);

    await store.toggleTodo(todo.id);
    expect(store.todoItems.single.done, isFalse);
    expect(store.todoItems.single.completedAt, isNull);
  });

  test('月份导航遵循方向规则并受五年范围限制', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final now = DateTime(2026, 7, 15, 10);
    final store = await _createStore(db, now: () => now);

    expect(store.firstNavigableMonth, DateTime(2024, 1));
    expect(store.lastNavigableMonth, DateTime(2029, 1));

    await store.selectDate(DateTime(2026, 7, 15));
    await store.navigateMonth(forward: true);
    expect(store.selectedDate, DateTime(2026, 8, 1));

    await store.navigateMonth(forward: false);
    expect(store.selectedDate, DateTime(2026, 7, 31));

    await store.selectDate(DateTime(2026, 12, 31));
    await store.navigateMonth(forward: true);
    expect(store.selectedDate, DateTime(2027, 1, 1));

    await store.selectDate(DateTime(2026, 3, 1));
    await store.navigateMonth(forward: false);
    expect(store.selectedDate, DateTime(2026, 2, 28));

    await store.selectDate(store.firstNavigableMonth);
    expect(store.canNavigateMonth(forward: false), isFalse);
    await store.navigateMonth(forward: false);
    expect(store.selectedDate, store.firstNavigableMonth);

    await store.selectDate(store.lastNavigableMonth);
    expect(store.canNavigateMonth(forward: true), isFalse);
    await store.navigateMonth(forward: true);
    expect(store.selectedDate, store.lastNavigableMonth);
  });

  test('月份导航加载目标日期已有的对话', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final local = SumiLocalDatabase(database: db);
    final chatDb = ChatDatabase(local);
    final conversation = await chatDb.createConversationForDate('2026-07-01');
    await chatDb.saveMessage(
      ChatMessage(
        id: 'july-message',
        conversationId: conversation.id,
        role: 'user',
        content: '七月的对话',
        createdAt: DateTime(2026, 7, 1, 9),
      ),
    );
    final store = await _createStore(db, now: () => DateTime(2026, 7, 15));

    await store.selectDate(DateTime(2026, 6, 30));
    await store.navigateMonth(forward: true);

    expect(store.selectedDate, DateTime(2026, 7, 1));
    expect(store.chatView.value.messages.single.content, '七月的对话');
  });

  testWidgets('月视图按钮切换月份并在边界禁用', (tester) async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final store = await _createStore(db, now: () => DateTime(2026, 7, 15));
    await store.selectDate(DateTime(2026, 7, 15));

    await tester.pumpWidget(
      SumiScope(
        store: store,
        child: const MaterialApp(home: Scaffold(body: MonthViewSheet())),
      ),
    );

    final previousButton = find.widgetWithIcon(
      IconButton,
      Icons.keyboard_arrow_left,
    );
    final nextButton = find.widgetWithIcon(
      IconButton,
      Icons.keyboard_arrow_right,
    );
    expect(previousButton, findsOneWidget);
    expect(nextButton, findsOneWidget);
    expect(find.text('7月'), findsOneWidget);

    await tester.tap(nextButton);
    await tester.pump();
    expect(store.selectedDate, DateTime(2026, 8, 1));
    expect(find.text('8月'), findsOneWidget);

    await store.selectDate(store.lastNavigableMonth);
    await tester.pump();
    expect(tester.widget<IconButton>(nextButton).onPressed, isNull);
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
    await store.deleteProject(projectId);
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
        MonthPlanItem(monthIndex: 0, title: '基础阶段', summary: '建立测试基础并完成练习'),
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
        MonthPlanItem(monthIndex: 0, title: '基础阶段', summary: '建立基础'),
      ],
      todayTodos: [TodoSeed(title: '阅读资料', date: today)],
    );

    await store.commitProjectPlan(request, null, plan);

    expect(store.projectList.single.name, '自动化测试入门');
    expect(store.projectList.single.goalSummary, '自动化测试入门');
  });
}
