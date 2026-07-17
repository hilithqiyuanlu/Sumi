import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import '../../utils/haptics.dart';

import '../../services/voice_input_service.dart';
import '../../store/sumi_store.dart';
import '../../theme/app_theme.dart';

/// 语音录制状态提示。
enum _VoiceHint { none, listening, cancel }

enum ChatInputMode { chat, todo }

/// 底部统一输入栏。
class ChatInput extends StatefulWidget {
  final ChatSendResult Function(String) onSend;
  final bool enabled;
  final bool isStreaming;
  final VoidCallback? onStopGenerating;
  final VoiceInputService? voiceService;
  final String? draftText;
  final int draftRevision;
  final ValueChanged<int>? onDraftApplied;
  final ValueChanged<String>? onTextChanged;
  final ChatInputMode mode;

  const ChatInput({
    super.key,
    required this.onSend,
    this.enabled = true,
    this.isStreaming = false,
    this.onStopGenerating,
    this.voiceService,
    this.draftText,
    this.draftRevision = 0,
    this.onDraftApplied,
    this.onTextChanged,
    this.mode = ChatInputMode.chat,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _inputSurfaceKey = GlobalKey();
  bool _hasText = false;
  bool _isInputEditing = false;

  // 语音状态
  bool _isRecording = false;
  _VoiceHint _voiceHint = _VoiceHint.none;
  String _voiceText = ''; // 录音前的文本（用于回退）
  String _voicePreviewText = '';
  bool _isFinalizingVoice = false;
  OverlayEntry? _voiceOverlayEntry;

  // 添加按钮按压动画（文件与图片功能暂未开放）。
  bool _attachmentPressed = false;

  // 长按语音手势检测
  Timer? _longPressTimer;
  Offset? _pointerDownPos;
  static const _longPressDuration = Duration(milliseconds: 500);
  static const _cancelSwipeThreshold = 60.0;

  VoiceInputService? get _voice => widget.voiceService;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
    _applyDraft(widget.draftText, widget.draftRevision);

    // 监听实时部分识别
    _voice?.onPartialResult = _handlePartialResult;
  }

  @override
  void dispose() {
    _removeVoiceOverlay();
    if (_voice?.onPartialResult == _handlePartialResult) {
      _voice?.onPartialResult = null;
    }
    _controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    _longPressTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChatInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.voiceService != widget.voiceService) {
      if (oldWidget.voiceService?.onPartialResult == _handlePartialResult) {
        oldWidget.voiceService?.onPartialResult = null;
      }
      _voice?.onPartialResult = _handlePartialResult;
    }
    final draft = widget.draftText;
    if (draft == null || widget.draftRevision == oldWidget.draftRevision) {
      return;
    }
    _applyDraft(draft, widget.draftRevision);
  }

  void _applyDraft(String? draft, int revision) {
    if (draft == null) return;
    _controller.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
    // 切换日期恢复空草稿时不应自动弹键盘或进入输入态；
    // 只有非空草稿（如点击建议）才切换到输入态并请求焦点。
    if (draft.isEmpty) {
      widget.onDraftApplied?.call(revision);
      return;
    }
    setState(() => _isInputEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.enabled && !widget.isStreaming) {
        _focusNode.requestFocus();
      }
      widget.onDraftApplied?.call(revision);
    });
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
    widget.onTextChanged?.call(_controller.text);
  }

  void _onFocusChanged() {
    if (!mounted || _isInputEditing == _focusNode.hasFocus) return;
    setState(() => _isInputEditing = _focusNode.hasFocus);
  }

  void _handlePartialResult(String text) {
    if (!_isRecording || !mounted) return;
    final preview = text.trim();
    if (preview == _voicePreviewText) return;
    setState(() => _voicePreviewText = preview);
    _voiceOverlayEntry?.markNeedsBuild();
  }

  void _showVoiceOverlay() {
    if (_voiceOverlayEntry != null) {
      _voiceOverlayEntry?.markNeedsBuild();
      return;
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(
      builder: (_) => _VoiceCaptureOverlay(
        inputRect: _inputSurfaceRect,
        text: _voicePreviewText,
        cancelling: _voiceHint == _VoiceHint.cancel,
        finalizing: _isFinalizingVoice,
        waitsForFinalResult: _voice?.usingLocalModel ?? false,
      ),
    );
    _voiceOverlayEntry = entry;
    overlay.insert(entry);
  }

  Rect? get _inputSurfaceRect {
    final box =
        _inputSurfaceKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _removeVoiceOverlay() {
    _voiceOverlayEntry?.remove();
    _voiceOverlayEntry = null;
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled || widget.isStreaming) return;
    H.click();

    final result = widget.onSend(text);
    if (result == ChatSendResult.accepted) _clearText();
  }

  void _clearText() {
    _controller.clear();
    _hasText = false;
    _voiceText = '';
  }

  void _tapAttachment() {
    H.click();
    setState(() => _attachmentPressed = true);
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _attachmentPressed = false);
    });
  }

  // ---------------------------------------------------------------------------
  // 长按语音 —— Listener + Timer（绕过 TextField 手势竞技场）
  // ---------------------------------------------------------------------------

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled || _isRecording) return;
    // Prevent TextField from claiming focus until this press is known to be a
    // short tap. A long press then enters voice without a keyboard flash.
    _focusNode.unfocus();
    _isInputEditing = false;
    _pointerDownPos = event.position;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(_longPressDuration, () {
      _longPressTimer = null;
      if (!mounted || _isRecording) return;
      H.medium();
      _startRecording();
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_pointerDownPos == null) return;

    if (_longPressTimer != null) {
      // 长按未触发 → 移动过远则取消
      final delta = event.position - _pointerDownPos!;
      if (delta.distance > _cancelSwipeThreshold) {
        _longPressTimer?.cancel();
        _longPressTimer = null;
      }
    } else if (_isRecording) {
      // 正在录音 → 上滑取消
      final dy = event.position.dy - _pointerDownPos!.dy;
      final wasCancel = _voiceHint == _VoiceHint.cancel;
      final isCancel = dy < -_cancelSwipeThreshold;
      if (isCancel != wasCancel) {
        H.light();
        setState(
          () =>
              _voiceHint = isCancel ? _VoiceHint.cancel : _VoiceHint.listening,
        );
        _voiceOverlayEntry?.markNeedsBuild();
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_longPressTimer != null) {
      // Short tap: restore ordinary TextField focus only after this pointer
      // sequence finishes, so its own tap recognizer cannot flash the keyboard.
      _longPressTimer?.cancel();
      _longPressTimer = null;
      _pointerDownPos = null;
      setState(() {
        // Reinsert the real TextField before requesting focus below.
        _isInputEditing = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.enabled && !widget.isStreaming) {
          _focusNode.requestFocus();
        }
      });
      return;
    }
    _pointerDownPos = null;
    if (_isRecording) {
      if (_voiceHint == _VoiceHint.cancel) {
        _cancelRecording();
      } else {
        _stopRecording();
      }
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _pointerDownPos = null;
    if (_isRecording) {
      _cancelRecording();
    } else if (mounted) {}
  }

  // ---------------------------------------------------------------------------
  // 语音
  // ---------------------------------------------------------------------------

  Future<void> _startRecording() async {
    if (_voice == null) return;
    _voiceText = _controller.text.trim();
    _voicePreviewText = '';
    _isFinalizingVoice = false;

    try {
      await _voice!.start();
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _voiceHint = _VoiceHint.listening;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isRecording) _showVoiceOverlay();
      });
    } on VoiceInputException catch (_) {
      if (!mounted) return;
      _setRecordingOff();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('无法使用语音识别，请检查麦克风权限'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _stopRecording() async {
    if (_voice == null || !_isRecording) return;

    try {
      setState(() => _isFinalizingVoice = true);
      _voiceOverlayEntry?.markNeedsBuild();
      final result = await _voice!.stop();
      if (!mounted) return;
      _setRecordingOff();

      if (result != null && result.text.isNotEmpty) {
        // 录音过程中已经允许取消；识别完成后直接提交，不弹出键盘。
        final combined = _voiceText.isNotEmpty
            ? '$_voiceText\n${result.text}'
            : result.text;
        final sendResult = widget.onSend(combined);
        if (sendResult == ChatSendResult.accepted) {
          _clearText();
        } else {
          // API 配置或忙碌等拒绝发送时，保留文字以免用户丢失内容。
          _controller.text = combined;
          _controller.selection = TextSelection.collapsed(
            offset: _controller.text.length,
          );
          setState(() {
            _hasText = true;
            _isInputEditing = false;
          });
        }
      }
    } on VoiceInputException catch (e) {
      if (!mounted) return;
      _setRecordingOff();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _cancelRecording() {
    _voice?.cancel();
    _setRecordingOff();
    // 恢复录音前的文本
    _controller.text = _voiceText;
    _voiceText = '';
    _hasText = _controller.text.trim().isNotEmpty;
  }

  void _setRecordingOff() {
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _voiceHint = _VoiceHint.none;
      _voicePreviewText = '';
      _isFinalizingVoice = false;
    });
    _removeVoiceOverlay();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  String get _placeholderText {
    if (_isRecording) return '正在收听…';
    return widget.mode == ChatInputMode.todo ? '新建事项' : '发消息或按住说话，带图也行';
  }

  @override
  Widget build(BuildContext context) {
    final showSendButton =
        widget.isStreaming || (_hasText && widget.enabled && !_isRecording);
    final hasVoice = _voice != null;
    // 已有内容时必须始终保留 TextField。否则失焦后会切回语音提示层，
    // 让“新建事项”或“发消息”盖住用户已经输入的文字。
    final voiceCapturesPointer = hasVoice && !_isInputEditing && !_hasText;
    final isCancelHint = _voiceHint == _VoiceHint.cancel;

    final voiceFill = isCancelHint ? error50 : primary50;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 悬浮输入栏
        Padding(
          padding: EdgeInsets.only(
            left: s16,
            right: s16,
            top: s16,
            bottom: MediaQuery.of(context).padding.bottom + s8,
          ),
          child: TextFieldTapRegion(
            child: AnimatedContainer(
              key: _inputSurfaceKey,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: _isRecording
                    ? voiceFill
                    : widget.mode == ChatInputMode.todo
                    ? primary50.withValues(alpha: 0.9)
                    : Colors.white.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(radiusPill),
                border: _isRecording
                    ? null
                    : Border.all(
                        color: widget.mode == ChatInputMode.todo
                            ? primary100
                            : Colors.white.withValues(alpha: 0.5),
                        width: 0.5,
                      ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 2),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 1,
                    offset: const Offset(0, 0),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radiusPill),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 添加文件或图片（暂不开放功能）。
                      Padding(
                        padding: const EdgeInsets.only(left: 14),
                        child: GestureDetector(
                          onTap: widget.enabled && !widget.isStreaming
                              ? _tapAttachment
                              : null,
                          child: AnimatedScale(
                            scale: _attachmentPressed ? 0.88 : 1.0,
                            duration: const Duration(milliseconds: 100),
                            curve: Curves.easeOutCubic,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: primary50,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: Icon(
                                  widget.mode == ChatInputMode.todo
                                      ? Icons.playlist_add_rounded
                                      : Icons.add_rounded,
                                  key: ValueKey(widget.mode),
                                  size: 24,
                                  color: primary500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // TextField + 语音长按
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          child: _isRecording
                              ? _VoiceRecordingPrompt(
                                  key: ValueKey(
                                    '${_voiceHint.name}-$_isFinalizingVoice',
                                  ),
                                  cancelling: isCancelHint,
                                  finalizing: _isFinalizingVoice,
                                  waitsForFinalResult:
                                      _voice?.usingLocalModel ?? false,
                                )
                              : voiceCapturesPointer
                              ? Listener(
                                  key: const ValueKey('voice-capture-layer'),
                                  behavior: HitTestBehavior.opaque,
                                  onPointerDown: _onPointerDown,
                                  onPointerMove: _onPointerMove,
                                  onPointerUp: _onPointerUp,
                                  onPointerCancel: _onPointerCancel,
                                  child: _VoiceIdlePrompt(mode: widget.mode),
                                )
                              : TextField(
                                  key: const ValueKey('text-input'),
                                  controller: _controller,
                                  focusNode: _focusNode,
                                  enabled:
                                      widget.enabled && !widget.isStreaming,
                                  maxLines: 4,
                                  minLines: 1,
                                  textInputAction: TextInputAction.newline,
                                  onTapOutside: (_) => _focusNode.unfocus(),
                                  style: const TextStyle(fontSize: 16),
                                  decoration: InputDecoration(
                                    hintText: _placeholderText,
                                    hintStyle: const TextStyle(
                                      fontSize: 16,
                                      color: textTertiary,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    filled: false,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: s10,
                                      vertical: 28,
                                    ),
                                  ),
                                  onSubmitted: (_) => _send(),
                                ),
                        ),
                      ),
                      // 内嵌发送按钮
                      AnimatedOpacity(
                        opacity: showSendButton ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 150),
                        child: AnimatedScale(
                          scale: showSendButton ? 1.0 : 0.6,
                          duration: const Duration(milliseconds: 150),
                          alignment: Alignment.center,
                          child: Material(
                            color: Colors.transparent,
                            shape: const CircleBorder(),
                            child: InkWell(
                              onTap: widget.isStreaming
                                  ? widget.onStopGenerating
                                  : showSendButton
                                  ? _send
                                  : null,
                              customBorder: const CircleBorder(),
                              overlayColor: WidgetStatePropertyAll(
                                Colors.white.withValues(alpha: 0.3),
                              ),
                              child: Container(
                                width: 44,
                                height: 44,
                                margin: const EdgeInsets.only(right: 14),
                                decoration: const BoxDecoration(
                                  color: mintDeep,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  widget.isStreaming ? Icons.stop : Icons.send,
                                  size: widget.isStreaming ? 20 : 22,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _VoiceRecordingPrompt extends StatelessWidget {
  final bool cancelling;
  final bool finalizing;
  final bool waitsForFinalResult;

  const _VoiceRecordingPrompt({
    super.key,
    required this.cancelling,
    required this.finalizing,
    required this.waitsForFinalResult,
  });

  @override
  Widget build(BuildContext context) {
    final color = cancelling ? danger : primary600;
    final icon = cancelling
        ? Icons.close_rounded
        : finalizing
        ? Icons.hourglass_top_rounded
        : Icons.mic_rounded;
    final label = cancelling
        ? '松开取消'
        : finalizing
        ? '正在转写…'
        : waitsForFinalResult
        ? '正在收听，松开转写'
        : '正在收听，松开发送';
    return SizedBox(
      height: 64,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: .82, end: 1.0),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeInOut,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              onEnd: () {},
              child: Icon(icon, color: color, size: iconMedium),
            ),
            const SizedBox(width: s8),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceCaptureOverlay extends StatelessWidget {
  final Rect? inputRect;
  final String text;
  final bool cancelling;
  final bool finalizing;
  final bool waitsForFinalResult;

  const _VoiceCaptureOverlay({
    required this.inputRect,
    required this.text,
    required this.cancelling,
    required this.finalizing,
    required this.waitsForFinalResult,
  });

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: CustomPaint(
        painter: _VoiceScrimPainter(inputRect),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: s24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: _VoiceTranscriptionCard(
                  text: text,
                  cancelling: cancelling,
                  finalizing: finalizing,
                  waitsForFinalResult: waitsForFinalResult,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _VoiceScrimPainter extends CustomPainter {
  final Rect? inputRect;

  const _VoiceScrimPainter(this.inputRect);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    final cutout = inputRect;
    if (cutout != null) {
      path.addRRect(
        RRect.fromRectAndRadius(cutout, const Radius.circular(radiusPill)),
      );
    }
    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: 0.32),
    );
  }

  @override
  bool shouldRepaint(_VoiceScrimPainter oldDelegate) =>
      oldDelegate.inputRect != inputRect;
}

class _VoiceTranscriptionCard extends StatelessWidget {
  final String text;
  final bool cancelling;
  final bool finalizing;
  final bool waitsForFinalResult;

  const _VoiceTranscriptionCard({
    required this.text,
    required this.cancelling,
    required this.finalizing,
    required this.waitsForFinalResult,
  });

  @override
  Widget build(BuildContext context) {
    final hasText = text.isNotEmpty;

    final title = cancelling
        ? '松开取消'
        : finalizing
        ? '转写中…'
        : waitsForFinalResult
        ? '正在录音'
        : '实时转写';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 160),
      padding: EdgeInsets.symmetric(
        horizontal: s16,
        vertical: hasText ? s16 : s14,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 状态行：icon + 状态文案
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cancelling ? error50 : primary50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  cancelling
                      ? Icons.close
                      : finalizing
                      ? Icons.hourglass_top
                      : Icons.mic_none_rounded,
                  size: 17,
                  color: cancelling ? danger : neutral600,
                ),
              ),
              const SizedBox(width: s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: cancelling ? danger : neutral600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 转写文字（仅有时显示）
          if (hasText && !cancelling) ...[
            const SizedBox(height: s10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 90),
              child: SingleChildScrollView(
                reverse: true,
                child: Text(
                  text,
                  style: const TextStyle(fontSize: 14, height: 1.5, color: ink),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VoiceIdlePrompt extends StatelessWidget {
  final ChatInputMode mode;
  const _VoiceIdlePrompt({required this.mode});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 64,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: s10),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (current, previousChildren) {
            return Stack(
              alignment: Alignment.centerLeft,
              children: <Widget>[
                ...previousChildren,
                // ignore: use_null_aware_elements
                if (current != null) current,
              ],
            );
          },
          child: Text(
            mode == ChatInputMode.todo ? '新建事项' : '发消息或按住说话，带图也行',
            key: ValueKey(mode),
            style: TextStyle(
              fontSize: 16,
              color: textTertiary,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ),
    ),
  );
}
