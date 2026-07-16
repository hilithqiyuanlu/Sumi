import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sumi/data/chat_database.dart';
import 'package:sumi/data/local_database.dart';
import 'package:sumi/data/signal_database.dart';
import 'package:sumi/models/models.dart';
import 'package:sumi/services/ai_contracts.dart';
import 'package:sumi/services/ai_service.dart';
import 'package:sumi/services/daily_reflection.dart';
import 'package:sumi/services/memory_extraction.dart';
import 'package:sumi/services/memory_service.dart';
import 'package:sumi/services/model_router.dart';

class _Structured implements StructuredGenerationCapability {
  int calls = 0;
  List<Map<String, Object?>>? receivedMessages;
  List<Map<String, Object?>>? receivedSignals;

  @override
  String? get lastError => null;

  @override
  Future<DailyReflectionResult?> generateDailyReflection({
    required String date,
    required List<Map<String, Object?>> messages,
    required List<Map<String, Object?>> signals,
  }) async {
    calls++;
    receivedMessages = messages;
    receivedSignals = signals;
    return const DailyReflectionResult(
      shortSummary: '完成了阅读练习，也明确了下一步要复盘错题。',
      reflection: '今天完成了阅读练习并讨论了学习安排，过程中确认了更适合先练习再复盘。明天可以继续完成错题整理，让学习节奏保持稳定。',
      highlights: ['完成阅读练习', '发现先练后复盘更顺手', '下一步整理错题'],
    );
  }

  @override
  Future<InputClassification?> classifyInput(
    String text, {
    String? draft,
  }) async => null;
  @override
  Future<SplitResult?> splitTodo(String text) async => null;
  @override
  Future<String?> polishTodo(String text) async => null;
  @override
  Future<MilestoneRecognition?> recognizeMilestone({
    required String message,
    required List<TodoItem> candidates,
  }) async => null;
  @override
  Future<PlanResult?> generatePlan({
    required String goal,
    required String level,
    required int cycleMonths,
    required int timeConstraint,
    required String startDate,
    required String assessmentReport,
    required String domainKnowledge,
    void Function(String chunk)? onProgress,
    void Function(AiStructuredStage stage)? onStage,
  }) async => null;
  @override
  Future<DailyTodoResult?> generateDailyTodos({
    required String monthPlanTitle,
    required String monthPlanSummary,
    required String date,
    required int timeConstraint,
    required int scheduledHours,
  }) async => null;
  @override
  Future<WeeklyTodoResult?> generateWeeklyTodos({
    required String monthPlanTitle,
    required String monthPlanSummary,
    required List<String> dates,
    required int timeConstraint,
    required int scheduledHours,
  }) async => null;
  @override
  Future<TodayLoadAnalysis?> analyzeTodayLoad({
    required String date,
    required List<Map<String, Object?>> todos,
    required List<Map<String, Object?>> futureDays,
  }) async => null;
  @override
  Future<TodayLoadScreening?> screenTodayLoad({
    required String date,
    required List<Map<String, Object?>> todos,
  }) async => null;
  @override
  Future<GoalAssessment?> assessGoal({
    required String goal,
    required String level,
    required int cycleMonths,
    required int timeConstraint,
    required String domainContext,
  }) async => null;
}

Future<Database> _database() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute(
    '''CREATE TABLE conversations (
    id TEXT PRIMARY KEY, title TEXT NOT NULL DEFAULT '', date_key TEXT,
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL, pinned INTEGER NOT NULL DEFAULT 0)''',
  );
  await db.execute(
    '''CREATE TABLE messages (
    id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL, role TEXT NOT NULL,
    content TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL,
    reasoning_content TEXT, tool_calls_json TEXT, tool_call_id TEXT, todo_result_json TEXT)''',
  );
  await db.execute('''CREATE TABLE signals (
    id INTEGER PRIMARY KEY AUTOINCREMENT, signal TEXT NOT NULL, time TEXT NOT NULL,
    context_json TEXT NOT NULL DEFAULT '{}', project_id TEXT, todo_id TEXT,
    domain TEXT, created_at TEXT NOT NULL)''');
  return db;
}

Future<void> _save(
  ChatDatabase chat,
  String id,
  String conversation,
  String role,
  String text,
) => chat.saveMessage(
  ChatMessage(
    id: id,
    conversationId: conversation,
    role: role,
    content: text,
    createdAt: DateTime(2026, 7, 14, 10),
  ),
);

void main() {
  setUpAll(sqfliteFfiInit);

  test('日结契约拒绝越界内容', () {
    expect(
      AiContracts.dailyReflection({
        'shortSummary': '太短',
        'reflection': '也太短',
        'highlights': ['短'],
      }).isValid,
      isFalse,
    );
    expect(
      AiContracts.dailyReflection({
        'shortSummary': '完成了阅读练习，并确定明天继续整理错题和复盘笔记。',
        'reflection':
            '今天完成阅读练习并讨论了后续安排，确认了练习后及时整理错题更适合当前节奏。明天继续整理笔记并做一次简短复盘，让进度更加清晰。',
        'highlights': ['完成阅读练习', '发现练后复盘更顺手', '下一步整理错题'],
      }).isValid,
      isTrue,
    );
  });

  test('日结只聚合指定日期的有效聊天和行为，不含工具或推理', () async {
    final db = await _database();
    addTearDown(db.close);
    final local = SumiLocalDatabase(database: db);
    final chat = ChatDatabase(local);
    final conversation = await chat.createConversationForDate('2026-07-14');
    await _save(chat, 'user', conversation.id, 'user', '我更适合上午练习。');
    await _save(chat, 'assistant', conversation.id, 'assistant', '可以先做阅读练习。');
    await _save(chat, 'tool', conversation.id, 'tool', '{"private":"tool"}');
    final signals = SignalDatabase(local);
    await signals.insert(
      UserSignal(
        signal: SignalType.todoCompleted,
        time: DateTime(2026, 7, 14, 12),
        contextJson: jsonEncode({'title': '阅读练习'}),
        createdAt: DateTime(2026, 7, 14, 12),
      ),
    );
    final structured = _Structured();
    final service = DailyReflectionService(
      database: DailyReflectionDatabase(local),
      chat: chat,
      signals: signals,
      structuredAi: () => structured,
      memory: MemoryService(local),
      memoryAi: () => null,
      onChanged: () {},
      onMemoryChanged: () {},
      now: () => DateTime(2026, 7, 16),
    );
    await service.generate('2026-07-14');
    expect(structured.receivedMessages, hasLength(2));
    expect(
      structured.receivedMessages!.any(
        (message) => message['content'] == '{"private":"tool"}',
      ),
      isFalse,
    );
    expect(structured.receivedSignals, hasLength(1));
    expect(
      (await service.reflectionFor(DateTime(2026, 7, 14)))?.status,
      DailyReflectionStatus.ready,
    );
  });

  test('成功日结不重复请求，日结补漏必须有用户原话', () async {
    final db = await _database();
    addTearDown(db.close);
    final local = SumiLocalDatabase(database: db);
    final memory = MemoryService(local);
    const invalid = MemoryExtractionDecision(
      action: MemoryExtractionAction.save,
      category: 'preference',
      content: '偏好晨间学习',
      quotedText: '不存在的句子',
    );
    expect(
      await memory.applyDailyBackfillDecision(
        messageId: 'm1',
        userMessage: '我上午精神更好。',
        decision: invalid,
      ),
      isFalse,
    );
    const valid = MemoryExtractionDecision(
      action: MemoryExtractionAction.save,
      category: 'preference',
      content: '偏好上午学习',
      quotedText: '我上午精神更好',
    );
    expect(
      await memory.applyDailyBackfillDecision(
        messageId: 'm1',
        userMessage: '我上午精神更好。',
        decision: valid,
      ),
      isTrue,
    );
    expect((await memory.list()).single.content, '偏好上午学习');
  });

  test('补跑按日期处理，单次最多生成两天', () async {
    final db = await _database();
    addTearDown(db.close);
    final local = SumiLocalDatabase(database: db);
    final signals = SignalDatabase(local);
    for (final day in [11, 12, 13]) {
      await signals.insert(
        UserSignal(
          signal: SignalType.todoCompleted,
          time: DateTime(2026, 7, day, 10),
          createdAt: DateTime(2026, 7, day, 10),
        ),
      );
    }
    final structured = _Structured();
    final service = DailyReflectionService(
      database: DailyReflectionDatabase(local),
      chat: ChatDatabase(local),
      signals: signals,
      structuredAi: () => structured,
      memory: MemoryService(local),
      memoryAi: () => null,
      onChanged: () {},
      onMemoryChanged: () {},
      now: () => DateTime(2026, 7, 16),
    );
    await service.runBacklog();
    expect(structured.calls, 2);
    expect(
      (await service.reflectionFor(DateTime(2026, 7, 11)))?.status,
      DailyReflectionStatus.ready,
    );
    expect(await service.reflectionFor(DateTime(2026, 7, 13)), isNull);
  });
}
