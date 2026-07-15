import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/voice_input_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/utils.dart';

/// 语音录制状态提示。
enum _VoiceHint { none, listening, cancel }

/// 底部输入栏 —— 支持 Sumi 对话 / Todo 事项两种模式。
class ChatInput extends StatefulWidget {
  final InputMode mode;
  final ValueChanged<String> onSend;
  final ValueChanged<String>? onAddTodo;
  final ValueChanged<InputMode>? onModeChanged;
  final bool enabled;
  final VoiceInputService? voiceService;
  final bool isFutureDate;

  const ChatInput({
    super.key,
    required this.mode,
    required this.onSend,
    this.onAddTodo,
    this.onModeChanged,
    this.enabled = true,
    this.voiceService,
    this.isFutureDate = false,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;

  // 语音状态
  bool _isRecording = false;
  _VoiceHint _voiceHint = _VoiceHint.none;
  String _voiceText = ''; // 录音前的文本（用于回退）
  Timer? _autoSendTimer;
  bool _userEditedAfterVoice = false;

  // 模式切换按钮按压动画
  bool _modePressed = false;

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

    // 监听实时部分识别
    _voice?.onPartialResult = (text) {
      if (!_isRecording) return;
      _controller.text = text;
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
    };
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    _autoSendTimer?.cancel();
    _longPressTimer?.cancel();
    super.dispose();
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

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    _controller.clear();
    _hasText = false;
    _voiceText = '';

    if (widget.mode == InputMode.todo) {
      widget.onAddTodo?.call(text);
    } else {
      widget.onSend(text);
    }
  }

  void _toggleMode() {
    HapticFeedback.selectionClick();
    setState(() => _modePressed = true);
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _modePressed = false);
    });
    final newMode = widget.mode == InputMode.chat ? InputMode.todo : InputMode.chat;
    widget.onModeChanged?.call(newMode);
  }

  // ---------------------------------------------------------------------------
  // 长按语音 —— Listener + Timer（绕过 TextField 手势竞技场）
  // ---------------------------------------------------------------------------

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled || _isRecording) return;
    _pointerDownPos = event.position;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(_longPressDuration, () {
      _longPressTimer = null;
      if (!mounted || _isRecording) return;
      HapticFeedback.mediumImpact();
      _startRecording();
      setState(() {});
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
        HapticFeedback.selectionClick();
        setState(() => _voiceHint =
            isCancel ? _VoiceHint.cancel : _VoiceHint.listening);
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_longPressTimer != null) {
      // 短按 → 取消计时器，不做任何事
      _longPressTimer?.cancel();
      _longPressTimer = null;
      _pointerDownPos = null;
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
        _controller.selection =
            TextSelection.collapsed(offset: _controller.text.length);
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
    return widget.mode == InputMode.todo
        ? '新增事项'
        : widget.isFutureDate
            ? '尽管说，不留聊天记录～'
            : '尽管说';
  }

  @override
  Widget build(BuildContext context) {
    final showSendButton = _hasText && widget.enabled && !_isRecording;
    final hasVoice = _voice != null;
    final isCancelHint = _voiceHint == _VoiceHint.cancel;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 录音状态提示条
        if (_isRecording)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: s16, vertical: s4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isCancelHint ? textTertiary : danger,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: s8),
                Flexible(
                  child: Text(
                    isCancelHint ? '松开取消' : '正在收听…松开发送',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: isCancelHint ? textTertiary : mintDeep,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // 悬浮输入栏
        Padding(
          padding: EdgeInsets.only(
            left: s16,
            right: s16,
            top: s16,
            bottom: MediaQuery.of(context).padding.bottom + s8,
          ),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(radiusPill),
              border: Border.all(
                color: _isRecording
                    ? mintDeep.withValues(alpha: 0.6)
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
                    // 模式切换（双态颜色 + 按压缩放）
                    Padding(
                      padding: const EdgeInsets.only(left: 14),
                      child: GestureDetector(
                        onTap: widget.enabled ? _toggleMode : null,
                        child: AnimatedScale(
                          scale: _modePressed ? 0.88 : 1.0,
                          duration: const Duration(milliseconds: 100),
                          curve: Curves.easeOutCubic,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOutCubic,
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: widget.mode == InputMode.todo
                                  ? primary500
                                  : primary50,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.swap_horiz_rounded,
                              size: 24,
                              color: widget.mode == InputMode.todo
                                  ? Colors.white
                                  : primary500,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // TextField + 语音长按
                    Expanded(
                      child: Listener(
                        onPointerDown: hasVoice ? _onPointerDown : null,
                        onPointerMove: hasVoice ? _onPointerMove : null,
                        onPointerUp: hasVoice ? _onPointerUp : null,
                        child: AbsorbPointer(
                          absorbing: _isRecording,
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            enabled: widget.enabled,
                            maxLines: 4,
                            minLines: 1,
                            textInputAction: TextInputAction.newline,
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
                            onTap: showSendButton ? _send : null,
                            customBorder: const CircleBorder(),
                            overlayColor: WidgetStatePropertyAll(
                                Colors.white.withValues(alpha: 0.3)),
                            child: Container(
                              width: 44,
                              height: 44,
                              margin: const EdgeInsets.only(right: 14),
                              decoration: const BoxDecoration(
                                color: mintDeep,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.send,
                                size: 22,
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
      ],
    );
  }
}
