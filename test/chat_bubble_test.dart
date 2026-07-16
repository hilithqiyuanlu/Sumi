import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sumi/features/chat/chat_bubble.dart';
import 'package:sumi/store/sumi_store.dart';

void main() {
  testWidgets('长按用户消息只显示编辑、取消和删除操作', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatBubble(
            content: '用户消息',
            isUser: true,
            onDelete: () {},
            onEdit: (_) async => ChatSendResult.accepted,
          ),
        ),
      ),
    );

    await tester.longPress(find.text('用户消息'));
    await tester.pumpAndSettle();

    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('记住这句话'), findsNothing);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
  });

  testWidgets('仅传入流式状态时显示光标', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatBubble(content: '正在输出', isUser: false, isStreaming: true),
        ),
      ),
    );

    expect(find.byType(ChatBubble), findsOneWidget);
  });
}
