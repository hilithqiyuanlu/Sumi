import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sumi/data/local_database.dart';
import 'package:sumi/services/memory_extraction.dart';
import 'package:sumi/services/memory_service.dart';
import 'package:sumi/services/user_model_service.dart';

class _CurrentMemoryCapability implements MemoryExtractionCapability {
  @override
  Future<MemoryExtractionDecision?> extractMemory({
    required String message,
    required List<MemoryExtractionCandidate> candidates,
  }) async => const MemoryExtractionDecision(
    action: MemoryExtractionAction.save,
    type: MemoryType.current,
    category: 'progress',
    content: '正在复习第一章',
    quotedText: '我正在复习第一章',
    confidence: .9,
  );
}

void main() {
  late Database db;
  late MemoryService memory;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    memory = MemoryService(SumiLocalDatabase(database: db));
    await memory.ensureTables();
  });

  tearDown(() => db.close());

  Future<MemoryItem> saveAutomatically({
    String messageId = 'message-1',
    String message = '我通常更适合短时练习。',
    MemoryType type = MemoryType.explicit,
    String category = 'preference',
    String content = '偏好短时练习',
  }) async {
    await memory.claimExtraction(messageId);
    final saved = await memory.applyExtractionDecision(
      messageId: messageId,
      userMessage: message,
      decision: MemoryExtractionDecision(
        action: MemoryExtractionAction.save,
        type: type,
        category: category,
        content: content,
        quotedText: message.substring(0, message.length - 1),
        confidence: .9,
      ),
      candidateReplaceIds: const {},
    );
    expect(saved, isTrue);
    return (await memory.list(includeHistorical: false)).single;
  }

  test('自动采集保留原话证据', () async {
    final item = await saveAutomatically();

    expect((await memory.list()).single.id, item.id);
    expect((await memory.evidenceFor(item.id)).single.summary, '我通常更适合短时练习');
    expect(await memory.sourceMessageIdsFor(['message-1']), {'message-1'});
  });

  test('同一消息自动采集只处理一次', () async {
    final first = await saveAutomatically(messageId: 'message-once');
    expect(await memory.claimExtraction('message-once'), isFalse);
    expect(await memory.list(), hasLength(1));
    expect(await memory.evidenceFor(first.id), hasLength(1));
  });

  test('编辑会切换类型，当前关注无需关联项目', () async {
    final item = await saveAutomatically();

    await memory.update(
      item.id,
      type: MemoryType.current,
      category: item.category,
      content: item.content,
    );
    var restored = (await memory.list()).single;
    expect(restored.type, MemoryType.current);
    expect(restored.category, 'progress');
    expect(restored.projectId, isNull);

    await memory.update(
      item.id,
      type: MemoryType.explicit,
      category: restored.category,
      content: restored.content,
    );
    restored = (await memory.list()).single;
    expect(restored.type, MemoryType.explicit);
    expect(restored.category, 'preference');
    expect(restored.projectId, isNull);
  });

  test('删除来源后清理无证据记忆并阻止迟到采集', () async {
    final item = await saveAutomatically(messageId: 'message-deleted');

    final deleted = await memory.removeMessageSources(['message-deleted']);
    expect(deleted, {item.id});
    expect(await memory.list(), isEmpty);
    expect(await memory.claimExtraction('message-deleted'), isFalse);
    await memory.finishExtraction('message-deleted', status: 'applied');
    final run = await db.query(
      'memory_extraction_runs',
      where: 'message_id = ?',
      whereArgs: ['message-deleted'],
    );
    expect(run.single['status'], 'cancelled');
  });

  test('删除一个来源时保留仍有其他原话证据的记忆', () async {
    const decision = MemoryExtractionDecision(
      action: MemoryExtractionAction.save,
      category: 'constraint',
      content: '晚上不安排任务',
      quotedText: '晚上不要安排任务',
      confidence: .9,
    );
    for (final id in ['message-a', 'message-b']) {
      await memory.claimExtraction(id);
      await memory.applyExtractionDecision(
        messageId: id,
        userMessage: '晚上不要安排任务。',
        decision: decision,
        candidateReplaceIds: const {},
      );
    }

    await memory.removeMessageSources(['message-a']);

    final item = (await memory.list()).single;
    expect(await memory.evidenceFor(item.id), hasLength(1));
    expect(await memory.sourceMessageIdsFor(['message-a']), isEmpty);
    expect(await memory.sourceMessageIdsFor(['message-b']), {'message-b'});
  });

  test('低置信度自动提取不会创建记忆', () async {
    await memory.claimExtraction('message-low');
    final applied = await memory.applyExtractionDecision(
      messageId: 'message-low',
      userMessage: '我可能喜欢短时练习。',
      decision: const MemoryExtractionDecision(
        action: MemoryExtractionAction.save,
        category: 'preference',
        content: '偏好短时练习',
        quotedText: '我可能喜欢短时练习',
        confidence: .7,
      ),
      candidateReplaceIds: const {},
    );

    expect(applied, isFalse);
    expect(await memory.list(), isEmpty);
    final diagnostics = await memory.extractionDiagnostics();
    expect(diagnostics.ignored, 1);
    expect(diagnostics.failed, 0);
  });

  test('技术失败最多可重新领取两次', () async {
    await memory.claimExtraction('message-retry');
    await memory.finishExtraction(
      'message-retry',
      status: 'failed',
      errorCategory: 'runtime',
    );

    expect(await memory.retryableExtractionIds(), ['message-retry']);
    expect(await memory.reclaimExtraction('message-retry'), isTrue);
    await memory.finishExtraction(
      'message-retry',
      status: 'failed',
      errorCategory: 'runtime',
    );
    expect(await memory.reclaimExtraction('message-retry'), isTrue);
    await memory.finishExtraction(
      'message-retry',
      status: 'failed',
      errorCategory: 'runtime',
    );
    expect(await memory.reclaimExtraction('message-retry'), isFalse);
  });

  test('当前关注可以在无项目时自动采集', () async {
    final service = MemoryExtractionService(
      memory: memory,
      capability: _CurrentMemoryCapability(),
      onMemoryChanged: () {},
      onMemorySaved: (_) {},
    );

    await service.process(messageId: 'message-project', message: '我正在复习第一章。');

    final item = (await memory.list()).single;
    expect(item.type, MemoryType.current);
    expect(item.projectId, isNull);
  });

  test('旧隐式建议迁入用户模型并按阈值生效', () async {
    await db.insert('memory_items', {
      'id': 'implicit-1',
      'type': 'implicit',
      'category': 'suggestion_topic',
      'content': 'plan',
      'status': 'active',
      'confidence': .9,
      'source': 'recommendation',
      'created_at': DateTime(2026, 7, 1).toIso8601String(),
    });
    final models = UserModelStore(SumiLocalDatabase(database: db));
    await models.syncFromImplicit(memory);

    final item = (await models.list()).single;
    expect(item.status, UserModelStatus.active);
    expect(await models.activeForSuggestions(), hasLength(1));
    await models.setStatus(item.id, UserModelStatus.disabled);
    expect((await models.list()).single.status, UserModelStatus.disabled);
    expect(await models.activeForSuggestions(), isEmpty);
    await models.syncFromImplicit(memory);
    expect((await models.list()).single.status, UserModelStatus.disabled);
    await models.delete(item.id);
    await models.syncFromImplicit(memory);
    expect(await models.list(), isEmpty);
    await models.clearAll();
    expect(await models.list(), isEmpty);
  });
}
