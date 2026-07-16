import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sumi/data/local_database.dart';
import 'package:sumi/data/schedule_proposal_database.dart';
import 'package:sumi/services/schedule_load_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  ScheduleRebalanceProposal proposal({
    ScheduleProposalStage stage = ScheduleProposalStage.attention,
    String? anchor,
  }) {
    return ScheduleRebalanceProposal(
      id: 'proposal-1',
      createdAt: DateTime(2026, 7, 20, 9),
      fingerprint: 'fingerprint-1',
      overloadScore: .82,
      reasons: const ['两个深度任务集中在今天'],
      moves: const [
        ScheduleMove(
          todoId: 'todo-1',
          fromDate: '2026-07-20',
          toDate: '2026-07-21',
          title: '整理阅读笔记',
        ),
      ],
      unscheduledTodoIds: const [],
      stage: stage,
      conversationId: 'conversation-1',
      displayAnchorMessageId: anchor,
    );
  }

  test('旧 JSON 没有阶段字段时按既有完整预览读取', () {
    final createdAt = DateTime(2026, 7, 20, 9);
    final restored = ScheduleRebalanceProposal.fromJson({
      'id': 'legacy',
      'createdAt': createdAt.toIso8601String(),
      'fingerprint': 'legacy-fingerprint',
      'overloadScore': .7,
      'reasons': ['旧方案'],
      'moves': const [],
      'unscheduledTodoIds': const [],
      'status': 'pending',
    });

    expect(restored.stage, ScheduleProposalStage.preview);
    expect(restored.updatedAt, createdAt);
    expect(restored.displayAnchorMessageId, isNull);
    expect(restored.completedAt, isNull);
  });

  test('阶段、锚点和完成信息可完整 JSON 往返', () {
    final completedAt = DateTime(2026, 7, 20, 10);
    final original = proposal(anchor: 'assistant-7').complete(
      movedCount: 1,
      completedAt: completedAt,
      displayAnchorMessageId: 'assistant-9',
    );
    final restored = ScheduleRebalanceProposal.fromJson(original.toJson());

    expect(restored.stage, ScheduleProposalStage.completed);
    expect(restored.status, ScheduleProposalStatus.accepted);
    expect(restored.completedMoveCount, 1);
    expect(restored.completedAt, completedAt);
    expect(restored.displayAnchorMessageId, 'assistant-9');
  });

  test('数据库保留完成卡并从对应会话隐藏已忽略卡', () async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(database.close);
    final proposals = ScheduleProposalDatabase(
      SumiLocalDatabase(database: database),
    );

    await proposals.save(proposal(anchor: 'assistant-1'));
    final preview = await proposals.updatePresentation(
      'proposal-1',
      stage: ScheduleProposalStage.preview,
    );
    expect(preview?.stage, ScheduleProposalStage.preview);
    expect(preview?.displayAnchorMessageId, 'assistant-1');

    final completed = await proposals.complete(
      'proposal-1',
      movedCount: 1,
      displayAnchorMessageId: 'assistant-2',
    );
    expect(completed?.status, ScheduleProposalStatus.accepted);
    expect(completed?.stage, ScheduleProposalStage.completed);
    expect(completed?.completedMoveCount, 1);
    expect(completed?.displayAnchorMessageId, 'assistant-2');
    expect(await proposals.latestPending(), isNull);

    final visible = await proposals.visibleForConversation('conversation-1');
    expect(visible, hasLength(1));
    expect(visible.single.stage, ScheduleProposalStage.completed);

    await proposals.updateStatus('proposal-1', ScheduleProposalStatus.dismissed);
    expect(
      await proposals.visibleForConversation('conversation-1'),
      isEmpty,
    );
  });
}
