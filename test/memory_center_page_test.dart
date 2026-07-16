import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sumi/features/memory/memory_center_page.dart';
import 'package:sumi/services/memory_service.dart';

void main() {
  testWidgets('编辑记忆自动聚焦到内容末尾且不显示项目或标签', (tester) async {
    const content = '我更适合短时练习';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MemoryEditorSheet(
            initialType: MemoryType.explicit,
            initialContent: content,
            onSave: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode?.hasFocus, isTrue);
    expect(field.controller?.selection.baseOffset, content.length);
    expect(field.controller?.selection.extentOffset, content.length);
    expect(find.text('关联项目'), findsNothing);
    expect(find.text('自定义标签'), findsNothing);
    expect(find.text('偏好'), findsNothing);
    expect(find.text('目标'), findsNothing);
    expect(find.text('限制'), findsNothing);
    expect(find.text('学习方式'), findsNothing);
    expect(find.text('进度'), findsNothing);
  });
}
