import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import '../../utils/haptics.dart';

import '../../services/voice_input_service.dart';
import '../../store/sumi_store.dart';
import '../../theme/app_theme.dart';

/// 语音录制状态提示。
enum _VoiceHint { none, listening, cancel }

/// 底部统一输入栏。
class ChatInput extends StatefulWidget {
  final ChatSendResult Function(String) onSend;
  final bool enabled;
  final bool isStreaming;
  final VoidCallback? onStopGenerating;
  final VoiceInputService? voiceService;
  final String? draftText;
  final int draftRevision;

  const ChatInput({
    super.key,
    required this.onSend,
    this.enabled = true,
    this.isStreaming = false,
    this.onStopGenerating,
    this.voiceService,
    this.draftText,
    this.draftRevision = 0,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  bool _isInputEditing = false;

  // 语音状态
  bool _isRecording = false;
  _VoiceHint _voiceHint = _VoiceHint.none;
  String _voiceText = ''; // 录音前的文本（用于回退）
  Timer? _autoSendTimer;
  bool _userEditedAfterVoice = false;

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
    _applyDraft(widget.draftText);

    // 监听实时部分识别
    _voice?.onPartialResult = (text) {
      if (!_isRecording) return;
      _controller.text = text;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    };
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    _autoSendTimer?.cancel();
    _longPressTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChatInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final draft = widget.draftText;
    if (draft == null || widget.draftRevision == oldWidget.draftRevision) {
      return;
    }
    _applyDraft(draft);
  }

  void _applyDraft(String? draft) {
    if (draft == null) return;
    _controller.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
    // A suggestion can arrive while the idle voice capture layer is visible.
    // Switch to the real field in the same frame so the draft is immediately
    // visible instead of waiting for a second tap.
    setState(() => _isInputEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.enabled && !widget.isStreaming) {
        _focusNode.requestFocus();
      }
    });
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
    // 录音结束后如果用户编辑了文字，取消自动发送
    if (!_isRecording && _voiceText.isNotEmpty) {
      if (_controller.text.trim() != _voiceText) {
        _userEditedAfterVoice = true;
        _autoSendTimer?.cancel();
      }
    }
  }

  void _onFocusChanged() {
    if (!mounted || _isInputEditing == _focusNode.hasFocus) return;
    setState(() => _isInputEditing = _focusNode.hasFocus);
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
    _autoSendTimer?.cancel();
    _userEditedAfterVoice = false;
    _voiceText = _controller.text.trim();

    try {
      await _voice!.start();
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _voiceHint = _VoiceHint.listening;
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
      final result = await _voice!.stop();
      if (!mounted) return;
      _setRecordingOff();

      if (result != null && result.text.isNotEmpty) {
        // 合并语音文字（保留录音前的文字）
        final combined = _voiceText.isNotEmpty
            ? '$_voiceText\n${result.text}'
            : result.text;
        _controller.text = combined;
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
        _voiceText = combined;
        _hasText = true;

        // 自动发送：0.3s 后若用户未编辑则发送
        _userEditedAfterVoice = false;
        _autoSendTimer?.cancel();
        _autoSendTimer = Timer(const Duration(milliseconds: 350), () {
          if (!_userEditedAfterVoice && mounted) {
            _send();
          }
        });
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
    });
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  String get _placeholderText {
    if (_isRecording) return '正在收听…';
    return '发消息或按住说话，带图也行';
  }

  @override
  Widget build(BuildContext context) {
    final showSendButton =
        widget.isStreaming || (_hasText && widget.enabled && !_isRecording);
    final hasVoice = _voice != null;
    final voiceCapturesPointer = hasVoice && !_isInputEditing;
    final isCancelHint = _voiceHint == _VoiceHint.cancel;

    final voiceFill = isCancelHint ? error50 : primary50;
    final voiceBorder = isCancelHint ? error100 : primary200;

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
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: _isRecording
                    ? voiceFill
                    : Colors.white.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(radiusPill),
                border: Border.all(
                  color: _isRecording
                      ? voiceBorder
                      : Colors.white.withValues(alpha: 0.5),
                  width: _isRecording ? 1 : 0.5,
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
                              child: Icon(
                                Icons.add_rounded,
                                size: 24,
                                color: primary500,
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
                                  key: ValueKey(_voiceHint),
                                  cancelling: isCancelHint,
                                )
                              : voiceCapturesPointer
                              ? Listener(
                                  key: const ValueKey('voice-capture-layer'),
                                  behavior: HitTestBehavior.opaque,
                                  onPointerDown: _onPointerDown,
                                  onPointerMove: _onPointerMove,
                                  onPointerUp: _onPointerUp,
                                  onPointerCancel: _onPointerCancel,
                                  child: const _VoiceIdlePrompt(),
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

  const _VoiceRecordingPrompt({super.key, required this.cancelling});

  @override
  Widget build(BuildContext context) {
    final color = cancelling ? danger : primary600;
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
              child: Icon(
                cancelling ? Icons.close_rounded : Icons.mic_rounded,
                color: color,
                size: iconMedium,
              ),
            ),
            const SizedBox(width: s8),
            Text(
              cancelling ? '松开取消' : '正在收听，松开发送',
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

class _VoiceIdlePrompt extends StatelessWidget {
  const _VoiceIdlePrompt();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 64,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: s10),
        child: Text(
          '发消息或按住说话，带图也行',
          style: TextStyle(
            fontSize: 16,
            color: textTertiary,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    ),
  );
}
