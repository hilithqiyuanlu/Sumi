import 'package:flutter_test/flutter_test.dart';
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
}
