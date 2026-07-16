import 'package:flutter_test/flutter_test.dart';
import 'package:sumi/models/models.dart';
import 'package:sumi/services/chat_tool_registry.dart';

void main() {
  test('关闭工具后不会进入模型可见 schema', () {
    final schemas = ChatToolRegistry.schemasFor(const {
      'read_todos',
      'create_study_timer',
    });
    final names = schemas
        .map((schema) => (schema['function'] as Map)['name'])
        .toSet();

    expect(names, {'read_todos', 'create_study_timer'});
    expect(names.contains('write_todo'), isFalse);
    expect(names.contains('start_project_generation'), isFalse);
  });

  test('创建事项是固定的系统工具', () {
    final tool = ChatToolRegistry.byName('write_todo');

    expect(tool?.system, isTrue);
  });

  test('旧设置恢复后仍保留系统工具', () {
    final settings = AppSettings.fromJson({
      'enabledTools': <Object?>['read_todos'],
    });

    expect(settings.enabledTools, contains('write_todo'));
  });
}
