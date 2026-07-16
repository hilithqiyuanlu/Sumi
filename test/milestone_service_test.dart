import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sumi/data/local_database.dart';
import 'package:sumi/models/models.dart';
import 'package:sumi/services/milestone_service.dart';

void main() {
  late Database db;
  late MilestoneService service;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''CREATE TABLE IF NOT EXISTS milestones (
      id TEXT PRIMARY KEY, project_id TEXT NOT NULL, todo_id TEXT NOT NULL,
      source_message_id TEXT NOT NULL, quote TEXT NOT NULL, todo_title TEXT NOT NULL,
      month_index INTEGER NOT NULL, occurred_at TEXT NOT NULL, memory_id TEXT,
      created_at TEXT NOT NULL, UNIQUE(source_message_id, todo_id))''');
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS pending_milestone_statements (
      message_id TEXT NOT NULL, todo_id TEXT NOT NULL, quote TEXT NOT NULL,
      occurred_at TEXT NOT NULL, created_at TEXT NOT NULL,
      UNIQUE(message_id, todo_id))''',
    );
    service = MilestoneService(SumiLocalDatabase(database: db));
  });

  tearDown(() => db.close());

  test('只为已完成项目 Todo 创建，并按来源去重', () async {
    final todo = TodoItem(
      id: 'todo-1',
      source: TodoSource.system,
      projectId: 'project-1',
      title: '完成第一课',
      done: true,
      createdAt: DateTime(2026, 7, 1),
    );
    final first = await service.create(
      todo: todo,
      sourceMessageId: 'msg-1',
      quote: '我终于完成第一课了',
      occurredAt: DateTime(2026, 7, 2),
      monthIndex: 0,
    );
    final duplicate = await service.create(
      todo: todo,
      sourceMessageId: 'msg-1',
      quote: '我终于完成第一课了',
      occurredAt: DateTime(2026, 7, 2),
      monthIndex: 0,
    );

    expect(first, isNotNull);
    expect(duplicate, isNull);
    expect(await service.forProjectMonth('project-1', 0), hasLength(1));
  });

  test('待匹配原话保留 Todo 关联', () async {
    await service.savePending(
      messageId: 'msg-1',
      todoId: 'todo-1',
      quote: '这一关我过了',
      occurredAt: DateTime(2026, 7, 2),
    );
    final pending = await service.pendingStatements();
    expect(pending.single.todoId, 'todo-1');
    expect(pending.single.quote, '这一关我过了');
  });

  test('删除 Todo 时同时清理待匹配原话和里程碑', () async {
    final todo = TodoItem(
      id: 'todo-1',
      source: TodoSource.system,
      projectId: 'project-1',
      title: '完成第一课',
      done: true,
      createdAt: DateTime(2026, 7, 1),
    );
    await service.savePending(
      messageId: 'msg-pending',
      todoId: todo.id,
      quote: '我过关了',
      occurredAt: DateTime(2026, 7, 2),
    );
    await service.create(
      todo: todo,
      sourceMessageId: 'msg-created',
      quote: '我完成第一课了',
      occurredAt: DateTime(2026, 7, 2),
      monthIndex: 0,
    );

    final removed = await service.deleteForTodo(todo.id);

    expect(removed, hasLength(1));
    expect(await service.pendingStatements(), isEmpty);
    expect(await service.forProjectMonth('project-1', 0), isEmpty);
  });

  test('删除来源消息后阻止迟到的待匹配记录和里程碑', () async {
    final todo = TodoItem(
      id: 'todo-1',
      source: TodoSource.system,
      projectId: 'project-1',
      title: '完成第一课',
      done: true,
      createdAt: DateTime(2026, 7, 1),
    );
    await service.deleteForSourceMessages(['msg-deleted']);

    await service.savePending(
      messageId: 'msg-deleted',
      todoId: todo.id,
      quote: '我完成第一课了',
      occurredAt: DateTime(2026, 7, 2),
    );
    final milestone = await service.create(
      todo: todo,
      sourceMessageId: 'msg-deleted',
      quote: '我完成第一课了',
      occurredAt: DateTime(2026, 7, 2),
      monthIndex: 0,
    );

    expect(await service.pendingStatements(), isEmpty);
    expect(milestone, isNull);
    expect(await service.forProjectMonth('project-1', 0), isEmpty);
  });
}
