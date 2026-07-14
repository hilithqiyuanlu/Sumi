import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/voice_input_service.dart';
import '../../theme/app_theme.dart';

/// 语音录制状态提示。
enum _VoiceHint { none, listening, cancel }

/// 底部输入栏 —— 文本输入 + 长按语音（无麦克风图标，隐藏逻辑）。
class ChatInput extends StatefulWidget {
  final ValueChanged<String> onSend;
  final bool enabled;
  final VoiceInputService? voiceService;

  const ChatInput({
    super.key,
    required this.onSend,
    this.enabled = true,
    this.voiceService,
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
    widget.onSend(text);
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

  @override
  Widget build(BuildContext context) {
    final showSendButton = _hasText && widget.enabled && !_isRecording;
    final hasVoice = _voice != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 录音状态提示条
        if (_isRecording)
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(vertical: s6, horizontal: s16),
            color: _voiceHint == _VoiceHint.cancel
                ? surfaceAlt
                : mint.withValues(alpha: 0.15),
            child: Text(
              _voiceHint == _VoiceHint.cancel ? '松开取消' : '正在收听…松开发送',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: _voiceHint == _VoiceHint.cancel
                    ? textTertiary
                    : mintDeep,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        // 输入栏
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(color: line.withValues(alpha: 0.3)),
            ),
          ),
          padding: EdgeInsets.only(
            left: s16,
            right: s16,
            top: s10,
            bottom: MediaQuery.of(context).padding.bottom + s10,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Listener(
                  onPointerDown:
                      hasVoice ? _onPointerDown : null,
                  onPointerMove:
                      hasVoice ? _onPointerMove : null,
                  onPointerUp:
                      hasVoice ? _onPointerUp : null,
                  child: AbsorbPointer(
                    absorbing: _isRecording,
                    child: Container(
                      constraints:
                          const BoxConstraints(maxHeight: 120),
                      decoration: BoxDecoration(
                        color: _isRecording
                            ? mint.withValues(alpha: 0.08)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(radiusPill),
                        border: Border.all(
                          color: _isRecording
                              ? mintDeep.withValues(alpha: 0.5)
                              : line.withValues(alpha: 0.3),
                        ),
                      ),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        enabled: widget.enabled,
                        maxLines: 4,
                        minLines: 1,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: _isRecording ? '正在收听…' : '尽管说',
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(
                            horizontal: s16,
                            vertical: s10,
                          ),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                  ),
                ),
              ),
              // 发送按钮（有文字且非录音时显示）
              if (showSendButton) ...[
                const SizedBox(width: s6),
                Material(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(radiusPill),
                  child: InkWell(
                    onTap: _send,
                    borderRadius: BorderRadius.circular(radiusPill),
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.send,
                        size: 20,
                        color: paper,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
