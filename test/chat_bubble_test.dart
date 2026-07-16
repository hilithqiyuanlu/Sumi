import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sumi/features/chat/chat_bubble.dart';
import 'package:sumi/store/sumi_store.dart';

void main() {
  testWidgets('长按用户消息显示编辑、取消和删除操作', (tester) async {
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
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
  });
}
