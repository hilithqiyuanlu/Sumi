import 'package:flutter_test/flutter_test.dart';
import 'package:sumi/services/ai_contracts.dart';

void main() {
  test('接受完整待办分类和时间', () {
    final result = AiContracts.inputClassification({
      'intent': 'createTodo',
      'confidence': 0.9,
      'title': '交作业',
      'date': '2026-07-17',
      'reminderTime': '09:00',
      'missingFields': <Object?>[],
    });

    expect(result.isValid, isTrue);
  });

  test('拒绝无效时间和意图', () {
    final result = AiContracts.inputClassification({
      'intent': 'unknown',
      'confidence': 1.2,
      'reminderTime': '9:00',
      'missingFields': <Object?>[],
    });

    expect(result.isValid, isFalse);
  });

  test('里程碑必须引用候选 Todo 和用户原话', () {
    final result = AiContracts.milestoneRecognition(
      {'confidence': 0.9, 'todoId': 'todo-1', 'quotedText': '我完成了第一课'},
      validTodoIds: {'todo-1'},
      userMessage: '今天我完成了第一课，感觉很有成就感。',
    );

    expect(result.isValid, isTrue);
  });

  test('里程碑拒绝候选外 Todo 和改写原话', () {
    final result = AiContracts.milestoneRecognition(
      {'confidence': 0.9, 'todoId': 'todo-2', 'quotedText': '我取得了巨大突破'},
      validTodoIds: {'todo-1'},
      userMessage: '我完成了第一课。',
    );

    expect(result.isValid, isFalse);
  });

  test('记忆提取要求原话和高置信度字段', () {
    final valid = AiContracts.memoryExtraction({
      'action': 'save',
      'type': 'explicit',
      'category': 'preference',
      'content': '偏好短时练习',
      'quotedText': '我通常更适合短时练习',
      'confidence': .9,
    });
    final invalid = AiContracts.memoryExtraction({
      'action': 'save',
      'type': 'explicit',
      'category': 'preference',
      'content': '偏好短时练习',
      'quotedText': '我通常更适合短时练习',
    });
    expect(valid.isValid, isTrue);
    expect(invalid.isValid, isFalse);
  });
}
