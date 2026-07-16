import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sumi/features/chat/chat_input.dart';
import 'package:sumi/services/voice_input_service.dart';
import 'package:sumi/store/sumi_store.dart';

class _FakeVoiceInputService extends VoiceInputService {
  final bool local;

  _FakeVoiceInputService({this.local = false});

  @override
  bool get usingLocalModel => local;

  @override
  Future<void> start() async {}

  @override
  Future<VoiceResult?> stop() async =>
      const VoiceResult(text: '这是最终识别结果', duration: Duration(seconds: 2));

  @override
  Future<void> cancel() async {}

  void emitPartial(String text) => onPartialResult?.call(text);

  @override
  void dispose() {}
}

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

  testWidgets('事项模式显示新建事项并使用浅蓝背景', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInput(
            mode: ChatInputMode.todo,
            onSend: (_) => ChatSendResult.accepted,
          ),
        ),
      ),
    );

    expect(find.text('新建事项'), findsOneWidget);
    expect(find.text('发消息或按住说话，带图也行'), findsNothing);
    expect(find.byIcon(Icons.playlist_add_rounded), findsOneWidget);
  });

  testWidgets('语音输入层失焦后仍显示已输入的事项文字', (tester) async {
    final voice = _FakeVoiceInputService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInput(
            mode: ChatInputMode.todo,
            voiceService: voice,
            onSend: (_) => ChatSendResult.accepted,
          ),
        ),
      ),
    );

    await tester.tap(find.text('新建事项'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '准备明天的阅读材料');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '准备明天的阅读材料');
  });

  testWidgets('聊天与事项模式切换时输入框纵向位置不变', (tester) async {
    var mode = ChatInputMode.chat;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return ChatInput(
                  mode: mode,
                  onSend: (_) => ChatSendResult.accepted,
                );
              },
            ),
          ),
        ),
      ),
    );

    final chatTop = tester.getTopLeft(find.byType(ChatInput)).dy;
    rebuild(() => mode = ChatInputMode.todo);
    await tester.pump(const Duration(milliseconds: 220));
    final todoTop = tester.getTopLeft(find.byType(ChatInput)).dy;

    expect(todoTop, chatTop);
    expect(find.text('新建事项'), findsOneWidget);
  });

  testWidgets('缺少 API Key 时保留聊天输入', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInput(onSend: (_) => ChatSendResult.missingApiKey),
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
        home: Scaffold(body: ChatInput(onSend: (_) => ChatSendResult.accepted)),
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

  testWidgets('建议草稿应用后会被消费，输入框重建时不会再次注入', (tester) async {
    String? draft = '帮我安排今天的任务';
    var showInput = true;
    StateSetter? rebuild;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return showInput
                  ? ChatInput(
                      draftText: draft,
                      draftRevision: 1,
                      onDraftApplied: (_) => setState(() => draft = null),
                      onSend: (_) => ChatSendResult.accepted,
                    )
                  : const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('帮我安排今天的任务'), findsOneWidget);
    expect(draft, isNull);

    rebuild!(() => showInput = false);
    await tester.pump();
    rebuild!(() => showInput = true);
    await tester.pump();

    final rebuiltField = tester.widget<TextField>(find.byType(TextField));
    expect(rebuiltField.controller?.text, isEmpty);
  });

  testWidgets('长按时中央显示实时转写浮层，遮罩不阻断松开手势', (tester) async {
    final voice = _FakeVoiceInputService();
    String? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInput(
            voiceService: voice,
            onSend: (text) {
              sent = text;
              return ChatSendResult.accepted;
            },
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('发消息或按住说话，带图也行')),
    );
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();

    expect(find.text('实时转写'), findsOneWidget);
    voice.emitPartial('这是实时捕捉的文字');
    await tester.pump();
    expect(find.text('这是实时捕捉的文字'), findsOneWidget);

    await gesture.up();
    await tester.pump();
    expect(find.text('实时转写'), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    expect(sent, '这是最终识别结果');
  });

  testWidgets('本地整段识别完成后直接发送，不弹出键盘', (tester) async {
    final voice = _FakeVoiceInputService(local: true);
    String? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInput(
            voiceService: voice,
            onSend: (text) {
              sent = text;
              return ChatSendResult.accepted;
            },
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('发消息或按住说话，带图也行')),
    );
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();

    expect(find.text('正在录音'), findsOneWidget);

    await gesture.up();
    await tester.pump();
    await tester.pump();

    expect(sent, '这是最终识别结果');
    expect(find.byType(TextField), findsNothing);
  });
}
