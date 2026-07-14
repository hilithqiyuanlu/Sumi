import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/voice_input_service.dart';
import '../../theme/app_theme.dart';
import 'voice_record_button.dart';

/// 语音录制状态提示。
enum _VoiceHint { none, listening, cancel }

/// 底部输入栏 —— 文本输入 + 语音录制按钮。
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

  // 上滑取消的回调（由 VoiceRecordButton 在 onCancel 中触发）
  void _onVoiceCancel() {
    _cancelRecording();
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
            padding: const EdgeInsets.symmetric(vertical: s6, horizontal: s16),
            color: _voiceHint == _VoiceHint.cancel
                ? Colors.grey.shade100
                : Colors.red.shade50,
            child: Text(
              _voiceHint == _VoiceHint.cancel ? '松开取消' : '正在收听…松开发送',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: _voiceHint == _VoiceHint.cancel
                    ? textTertiary
                    : Colors.red.shade700,
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
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  decoration: BoxDecoration(
                    color: _isRecording ? Colors.red.shade50 : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _isRecording
                          ? Colors.red.withValues(alpha: 0.3)
                          : line.withValues(alpha: 0.5),
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
                      hintText:
                          _isRecording ? '正在收听…' : '和 Sumi 聊聊…',
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: s16,
                        vertical: s10,
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
              ),
              // 麦克风按钮
              if (hasVoice) ...[
                const SizedBox(width: s6),
                VoiceRecordButton(
                  enabled: widget.enabled,
                  isRecording: _isRecording,
                  onStart: _startRecording,
                  onStop: _stopRecording,
                  onCancel: _onVoiceCancel,
                ),
              ],
              // 发送按钮
              if (showSendButton) ...[
                const SizedBox(width: s6),
                Material(
                  color: mintDeep,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    onTap: _send,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.send_rounded,
                        size: 20,
                        color: Colors.white,
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
