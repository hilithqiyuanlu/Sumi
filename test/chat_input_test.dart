import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sumi/features/chat/chat_input.dart';
import 'package:sumi/store/sumi_store.dart';
import 'package:sumi/utils/utils.dart';

void main() {
  testWidgets('缺少 API Key 时保留聊天输入', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInput(
            mode: InputMode.chat,
            onSend: (_) => ChatSendResult.missingApiKey,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '不要丢失这段文字');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '不要丢失这段文字');
  });

  testWidgets('消息被接受后清空聊天输入', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInput(
            mode: InputMode.chat,
            onSend: (_) => ChatSendResult.accepted,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '发送这段文字');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isEmpty);
  });
}
