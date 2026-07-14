import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/voice_input_service.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import 'split_confirm_sheet.dart';

/// 语音录制状态提示。
enum _VoiceHint { none, listening, cancel }

/// 底部输入栏 —— 创建用户 todo，>18 字触发 AI 拆分 / 凝练。支持长按语音输入。
class TodoInput extends StatefulWidget {
  final VoiceInputService? voiceService;

  const TodoInput({super.key, this.voiceService});

  @override
  State<TodoInput> createState() => _TodoInputState();
}

class _TodoInputState extends State<TodoInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  bool _loading = false;

  // 语音状态
  bool _isRecording = false;
  _VoiceHint _voiceHint = _VoiceHint.none;
  String _voiceText = '';
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
    if (!_isRecording && _voiceText.isNotEmpty) {
      if (_controller.text.trim() != _voiceText) {
        _userEditedAfterVoice = true;
        _autoSendTimer?.cancel();
      }
    }
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final store = SumiScope.read(context);

    if (text.length <= 18) {
      store.addUserTodo(text);
      _controller.clear();
      return;
    }

    setState(() => _loading = true);

    try {
      final result = await store.splitAndAddTodo(text);

      if (!mounted) return;

      if (result != null && result.split) {
        await showSplitConfirmSheet(context, store, result.items);
      }
      _controller.clear();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 长按语音 —— Listener + Timer
  // ---------------------------------------------------------------------------

  void _onPointerDown(PointerDownEvent event) {
    if (_loading || _isRecording) return;
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
      final delta = event.position - _pointerDownPos!;
      if (delta.distance > _cancelSwipeThreshold) {
        _longPressTimer?.cancel();
        _longPressTimer = null;
      }
    } else if (_isRecording) {
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
        final combined = _voiceText.isNotEmpty
            ? '$_voiceText\n${result.text}'
            : result.text;
        _controller.text = combined;
        _controller.selection =
            TextSelection.collapsed(offset: _controller.text.length);
        _voiceText = combined;
        _hasText = true;

        // 自动提交：0.3s 后若用户未编辑则提交
        _userEditedAfterVoice = false;
        _autoSendTimer?.cancel();
        _autoSendTimer = Timer(const Duration(milliseconds: 350), () {
          if (!_userEditedAfterVoice && mounted) {
            _submit();
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
    final showSendButton =
        _hasText && !_loading && !_isRecording;
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
            color: paper,
            border: Border(
              top: BorderSide(color: line.withValues(alpha: 0.3)),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            s16,
            s10,
            s16,
            MediaQuery.of(context).padding.bottom + s10,
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
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        enabled: !_loading,
                        decoration: InputDecoration(
                          hintText: _isRecording ? '正在收听…' : '尽管说',
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: s16,
                            vertical: s10,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (showSendButton) ...[
                const SizedBox(width: s8),
                Material(
                  color: primary500,
                  borderRadius: BorderRadius.circular(radiusPill),
                  child: InkWell(
                    onTap: _submit,
                    borderRadius: BorderRadius.circular(radiusPill),
                    child: Container(
                      width: sizeButtonMd,
                      height: sizeButtonMd,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.send,
                        size: iconMedium,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ] else if (_loading) ...[
                const SizedBox(width: s8),
                Padding(
                  padding: const EdgeInsets.all(s10),
                  child: SizedBox(
                    width: sizeButtonMd,
                    height: sizeButtonMd,
                    child: const CircularProgressIndicator(
                        strokeWidth: 2, color: primary500),
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
