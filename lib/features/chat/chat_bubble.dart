import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/haptics.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../theme/app_theme.dart';
import '../../utils/utils.dart';
import '../../models/models.dart';
import '../../services/timer_controller.dart';
import '../../services/project_generation_controller.dart';
import '../../services/project_generation.dart';
import '../../store/sumi_store.dart';

/// 聊天气泡组件 —— 支持用户（右侧 mint）和 AI（左侧白色）两种样式。
class ChatBubble extends StatelessWidget {
  final String content;
  final bool isUser;
  final bool isStreaming;
  final DateTime? timestamp;
  final String? activityLabel;
  final String? toolCallsJson;
  final String? todoResultJson;
  final VoidCallback? onOpenTodo;
  final bool showMilestoneSaved;
  final bool showMemorySaved;
  final VoidCallback? onDelete;
  final Future<ChatSendResult> Function(String content)? onEdit;
  final TimerController? timerController;
  final Future<void> Function(String id)? onStartTimer;
  final Future<void> Function(String id)? onPauseTimer;
  final Future<void> Function(String id)? onFinishTimer;
  final ProjectGenerationController? projectGenerationController;

  const ChatBubble({
    super.key,
    required this.content,
    required this.isUser,
    this.isStreaming = false,
    this.timestamp,
    this.activityLabel,
    this.toolCallsJson,
    this.todoResultJson,
    this.onOpenTodo,
    this.showMilestoneSaved = false,
    this.showMemorySaved = false,
    this.onDelete,
    this.onEdit,
    this.timerController,
    this.onStartTimer,
    this.onPauseTimer,
    this.onFinishTimer,
    this.projectGenerationController,
  });

  @override
  Widget build(BuildContext context) {
    final alignment = isUser
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: s16, vertical: s6),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          // 用户消息时间坐标（居中显示）
          if (isUser && timestamp != null)
            Align(
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.only(bottom: s4),
                child: Text(
                  '${timestamp!.hour.toString().padLeft(2, '0')}:${timestamp!.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: textTertiary,
                  ),
                ),
              ),
            ),
          // 工具调用指示（仅 AI 且有 tool_calls 时显示，简洁样式）
          if (!isUser && toolCallsJson != null && toolCallsJson!.isNotEmpty)
            _ToolCallIndicator(toolCallsJson: toolCallsJson!),
          if (!isUser && todoResultJson != null)
            _TodoResultCard(json: todoResultJson!, onOpen: onOpenTodo),
          if (!isUser && toolCallsJson != null && timerController != null)
            _StudyTimerFromToolCalls(
              toolCallsJson: toolCallsJson!,
              controller: timerController!,
              onStart: onStartTimer,
              onPause: onPauseTimer,
              onFinish: onFinishTimer,
            ),
          if (!isUser &&
              toolCallsJson != null &&
              projectGenerationController != null)
            _ProjectGenerationFromToolCalls(
              toolCallsJson: toolCallsJson!,
              controller: projectGenerationController!,
            ),
          // 气泡（用户消息可删除；最新一条还可编辑后重新发送）
          if (todoResultJson == null)
            GestureDetector(
              onLongPress: isUser
                  ? () => _showUserMessageActions(context)
                  : () => _copyContent(context),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.78,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: s12,
                  vertical: s10,
                ),
                decoration: BoxDecoration(
                  color: isUser ? mint : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(isUser ? radius20 : s4),
                    topRight: Radius.circular(isUser ? s4 : radius20),
                    bottomLeft: const Radius.circular(radius20),
                    bottomRight: const Radius.circular(radius20),
                  ),
                  border: Border.all(
                    color: isUser
                        ? Colors.transparent
                        : line.withValues(alpha: 0.3),
                  ),
                  boxShadow: isUser
                      ? null
                      : const [
                          BoxShadow(
                            color: Color(0x080E1115),
                            offset: Offset(0, 1),
                            blurRadius: 3,
                          ),
                        ],
                ),
                child: _buildContent(),
              ),
            ),
          if (isUser && (showMilestoneSaved || showMemorySaved))
            const _MilestoneSavedHint(),
        ],
      ),
    );
  }

  void _showUserMessageActions(BuildContext context) {
    H.medium();
    if (onDelete == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusCard)),
        ),
        title: const Text(
          '删除这条对话？',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        content: const Text(
          '将同时删除这一来一回的全部内容，包括工具信息。',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          if (onEdit != null)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _editAndResend(context);
              },
              child: const Text('编辑'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              onDelete!.call();
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _copyContent(BuildContext context) {
    H.medium();
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _editAndResend(BuildContext context) async {
    final controller = TextEditingController(text: content);
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    final editedContent = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusCard)),
        ),
        title: const Text(
          '编辑消息',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('重新发送会移除这条消息及之后的对话。', style: TextStyle(fontSize: 14)),
            const SizedBox(height: s12),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 2,
              maxLines: 6,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(hintText: '输入消息'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('重新发送'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (editedContent == null || !context.mounted) return;
    final result = await onEdit?.call(editedContent);
    if (!context.mounted ||
        result == null ||
        result == ChatSendResult.accepted) {
      return;
    }
    final message = switch (result) {
      ChatSendResult.empty => '消息不能为空',
      ChatSendResult.busy => '正在生成回复，请稍后再编辑',
      ChatSendResult.missingApiKey => '请先设置 DeepSeek API Key',
      ChatSendResult.accepted => '',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Widget _buildContent() {
    if (content.isEmpty && isStreaming) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: mintDeep),
          ),
          const SizedBox(width: s8),
          Text(
            activityLabel ?? '正在生成回复',
            style: const TextStyle(fontSize: 13, color: textTertiary),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 用户消息保持纯文本，AI 消息用 Markdown 渲染
        if (isUser)
          Text(
            content,
            style: const TextStyle(fontSize: 15, height: 1.5, color: ink),
          )
        else
          MarkdownBody(
            data: content,
            selectable: true,
            styleSheet: _mdStyleSheet,
          ),
        if (isStreaming && activityLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: s8),
            child: Text(
              activityLabel!,
              style: const TextStyle(fontSize: 12, color: textTertiary),
            ),
          ),
        if (isStreaming)
          const Padding(
            padding: EdgeInsets.only(top: s2),
            child: _Cursor(),
          ),
      ],
    );
  }

  static final MarkdownStyleSheet _mdStyleSheet = MarkdownStyleSheet(
    p: const TextStyle(fontSize: 15, height: 1.5, color: ink),
    strong: const TextStyle(
      fontSize: 15,
      height: 1.5,
      color: ink,
      fontWeight: FontWeight.w600,
    ),
    code: TextStyle(
      fontSize: 13,
      color: textTertiary,
      backgroundColor: surfaceAlt,
      fontFamily: 'monospace',
    ),
    codeblockDecoration: BoxDecoration(
      color: surfaceAlt,
      borderRadius: BorderRadius.circular(radius8),
    ),
    h1: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ink),
    h2: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ink),
    h3: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ink),
    listBullet: const TextStyle(fontSize: 15, color: ink),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: line.withValues(alpha: 0.5), width: 1),
      ),
    ),
  );
}

class _MilestoneSavedHint extends StatelessWidget {
  const _MilestoneSavedHint();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: s4),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.bookmark_added_outlined, size: 14, color: primary500),
        SizedBox(width: s4),
        Text('已记住', style: TextStyle(fontSize: 12, color: primary500)),
      ],
    ),
  );
}

class _TodoResultCard extends StatelessWidget {
  final String json;
  final VoidCallback? onOpen;

  const _TodoResultCard({required this.json, this.onOpen});

  @override
  Widget build(BuildContext context) {
    try {
      final data = jsonDecode(json) as Map<String, Object?>;
      final title = data['title'] as String? ?? '事项';
      final date = data['date'] as String? ?? '';
      final time = data['reminderTime'] as String?;
      return GestureDetector(
        onTap: onOpen,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.78,
          margin: const EdgeInsets.only(bottom: s4),
          padding: const EdgeInsets.symmetric(horizontal: s12, vertical: s10),
          decoration: BoxDecoration(
            color: primary50,
            borderRadius: BorderRadius.circular(radius8),
            border: Border.all(color: primary100),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: primary500),
              const SizedBox(width: s8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '已创建待办',
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      [date, time]
                          .whereType<String>()
                          .where((v) => v.isNotEmpty)
                          .join('  '),
                      style: const TextStyle(fontSize: 12, color: textTertiary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: textTertiary),
            ],
          ),
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }
}

/// 流式输出光标。
class _Cursor extends StatefulWidget {
  const _Cursor();

  @override
  State<_Cursor> createState() => _CursorState();
}

class _CursorState extends State<_Cursor> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _controller.value,
          child: Container(
            width: 2,
            height: 16,
            decoration: BoxDecoration(
              color: mintDeep,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 工具调用指示（简洁版）
// ---------------------------------------------------------------------------

class _ToolCallIndicator extends StatelessWidget {
  final String toolCallsJson;
  const _ToolCallIndicator({required this.toolCallsJson});

  @override
  Widget build(BuildContext context) {
    List<String> names = [];
    try {
      final list = jsonDecode(toolCallsJson) as List<Object?>;
      for (final item in list) {
        if (item is Map<String, Object?>) {
          final func = item['function'] as Map<String, Object?>?;
          final name = func?['name'] as String?;
          if (name != null) {
            names.add(toolDisplayName(name));
          }
        }
      }
    } catch (_) {}

    if (names.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: s4),
      child: GestureDetector(
        onTap: () {}, // 无操作，仅视觉提示
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          padding: const EdgeInsets.symmetric(horizontal: s8, vertical: s4),
          decoration: BoxDecoration(
            color: mint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(s6),
          ),
          child: Text(
            names.join(" · "),
            style: const TextStyle(
              fontSize: 11,
              color: mintDeep,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _StudyTimerFromToolCalls extends StatelessWidget {
  final String toolCallsJson;
  final TimerController controller;
  final Future<void> Function(String id)? onStart;
  final Future<void> Function(String id)? onPause;
  final Future<void> Function(String id)? onFinish;

  const _StudyTimerFromToolCalls({
    required this.toolCallsJson,
    required this.controller,
    this.onStart,
    this.onPause,
    this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    String? toolCallId;
    try {
      final calls = jsonDecode(toolCallsJson) as List<Object?>;
      for (final call in calls) {
        if (call is Map<String, Object?> &&
            ((call['function'] as Map<String, Object?>?)?['name'] ==
                'create_study_timer')) {
          toolCallId = call['id'] as String?;
          break;
        }
      }
    } catch (_) {}
    if (toolCallId == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final timer = controller.byToolCallId(toolCallId!);
        if (timer == null) return const SizedBox.shrink();
        return _StudyTimerCard(
          timer: timer,
          onStart: onStart,
          onPause: onPause,
          onFinish: onFinish,
        );
      },
    );
  }
}

class _StudyTimerCard extends StatelessWidget {
  final StudyTimer timer;
  final Future<void> Function(String id)? onStart;
  final Future<void> Function(String id)? onPause;
  final Future<void> Function(String id)? onFinish;

  const _StudyTimerCard({
    required this.timer,
    this.onStart,
    this.onPause,
    this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = timer.remainingAt(DateTime.now());
    final isAlarm = timer.kind == StudyTimerKind.alarm;
    final finished =
        timer.status == StudyTimerStatus.completed ||
        timer.status == StudyTimerStatus.cancelled;
    final running = timer.status == StudyTimerStatus.running;
    // Completed timers preserve the actual remaining duration at the moment
    // the user stopped, so this remains accurate after an app restart.
    final elapsed = (timer.totalSeconds - remaining)
        .clamp(0, timer.totalSeconds)
        .toInt();
    final display = switch (timer.status) {
      StudyTimerStatus.completed when isAlarm => _clock(timer.alertAt),
      StudyTimerStatus.completed => '${elapsed ~/ 60}min',
      _ => _countdownLabel(remaining),
    };
    return Container(
      width: MediaQuery.of(context).size.width * 0.78,
      margin: const EdgeInsets.only(bottom: s4),
      padding: const EdgeInsets.symmetric(horizontal: s10, vertical: s8),
      decoration: BoxDecoration(
        color: primary50,
        borderRadius: BorderRadius.circular(radius8),
        border: Border.all(color: primary100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isAlarm ? Icons.alarm_outlined : Icons.timer_outlined,
                size: iconMedium,
                color: primary500,
              ),
              const SizedBox(width: s8),
              Expanded(
                child: Text(
                  timer.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                display,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: primary700,
                ),
              ),
              if (!isAlarm && !finished) ...[
                const SizedBox(width: s4),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: running ? '暂停' : '开始',
                  onPressed: running
                      ? () => onPause?.call(timer.id)
                      : () => onStart?.call(timer.id),
                  icon: Icon(running ? Icons.pause : Icons.play_arrow),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '完成',
                  onPressed: () => onFinish?.call(timer.id),
                  icon: const Icon(Icons.stop_circle_outlined),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(switch (timer.status) {
            StudyTimerStatus.ready => '准备开始',
            StudyTimerStatus.running when isAlarm =>
              '将在 ${_clock(timer.alertAt)} 提醒',
            StudyTimerStatus.running => '正在计时',
            StudyTimerStatus.paused => '已暂停',
            StudyTimerStatus.completed when isAlarm => '闹钟已到',
            StudyTimerStatus.completed => '本次学习 ${_durationLabel(elapsed)}',
            StudyTimerStatus.cancelled => '已取消',
          }, style: const TextStyle(fontSize: 12, color: textTertiary)),
        ],
      ),
    );
  }

  String _durationLabel(int seconds) {
    final minutes = seconds ~/ 60;
    if (minutes == 0) return '$seconds 秒';
    return '$minutes 分钟';
  }

  String _countdownLabel(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainder';
  }

  String _clock(DateTime? value) {
    if (value == null) return '设定时间';
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _ProjectGenerationFromToolCalls extends StatelessWidget {
  final String toolCallsJson;
  final ProjectGenerationController controller;

  const _ProjectGenerationFromToolCalls({
    required this.toolCallsJson,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    String? toolCallId;
    try {
      final calls = jsonDecode(toolCallsJson) as List<Object?>;
      for (final call in calls) {
        if (call is Map<String, Object?> &&
            ((call['function'] as Map<String, Object?>?)?['name'] ==
                'start_project_generation')) {
          toolCallId = call['id'] as String?;
          break;
        }
      }
    } catch (_) {}
    if (toolCallId == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final session = controller.forToolCall(toolCallId!);
        if (session == null) return const SizedBox.shrink();
        return _ProjectGenerationCard(state: session.state);
      },
    );
  }
}

class _ProjectGenerationCard extends StatelessWidget {
  final ProjectGenerationState state;
  const _ProjectGenerationCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final stages = const [
      ProjectGenerationStage.searching,
      ProjectGenerationStage.assessing,
      ProjectGenerationStage.awaitingConfirmation,
      ProjectGenerationStage.planning,
      ProjectGenerationStage.validating,
      ProjectGenerationStage.saving,
    ];
    final activeIndex = stages.indexOf(state.stage);
    return Container(
      width: MediaQuery.of(context).size.width * 0.78,
      margin: const EdgeInsets.only(bottom: s6),
      padding: const EdgeInsets.all(s12),
      decoration: BoxDecoration(
        color: primary50,
        borderRadius: BorderRadius.circular(radius8),
        border: Border.all(color: primary100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, size: iconMedium, color: primary500),
              SizedBox(width: s8),
              Text('项目生成', style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: s8),
          Text(state.status, style: const TextStyle(fontSize: 13, color: ink)),
          const SizedBox(height: s8),
          for (var index = 0; index < stages.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: s4),
              child: Row(
                children: [
                  Icon(
                    index < activeIndex
                        ? Icons.check_circle
                        : index == activeIndex
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 15,
                    color: index <= activeIndex ? primary500 : textSecondary,
                  ),
                  const SizedBox(width: s6),
                  Text(switch (stages[index]) {
                    ProjectGenerationStage.searching => '资料检索',
                    ProjectGenerationStage.assessing => '目标评估',
                    ProjectGenerationStage.awaitingConfirmation => '等待确认',
                    ProjectGenerationStage.planning => '计划生成',
                    ProjectGenerationStage.validating => '结构校验',
                    ProjectGenerationStage.saving => '保存项目',
                    _ => '',
                  }, style: const TextStyle(fontSize: 12, color: textTertiary)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
