import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sumi/features/chat/chat_input.dart';
import 'package:sumi/store/sumi_store.dart';

void main() {
  testWidgets('显示统一提示和添加按钮', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChatInput(onSend: (_) => ChatSendResult.accepted)),
      ),
    );

    expect(find.text('发消息或按住说话，带图也行'), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('缺少 API Key 时保留聊天输入', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInput(
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

  testWidgets('生成中显示停止按钮并触发停止回调', (tester) async {
    var stopped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInput(
            isStreaming: true,
            onSend: (_) => ChatSendResult.busy,
            onStopGenerating: () => stopped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.stop));
    expect(stopped, isTrue);
  });

  testWidgets('生成中禁用输入，并可由建议填入草稿', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInput(
            isStreaming: true,
            draftText: '稍后发送的内容',
            draftRevision: 1,
            onSend: (_) => ChatSendResult.busy,
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);
    expect(field.controller?.text, '稍后发送的内容');
    expect(find.byIcon(Icons.stop), findsOneWidget);
  });

  testWidgets('外部建议草稿会立即显示，不需要再次点击输入框', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInput(
            draftText: '帮我分析今天先做什么',
            draftRevision: 1,
            onSend: (_) => ChatSendResult.accepted,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('帮我分析今天先做什么'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '帮我分析今天先做什么');
  });
}
