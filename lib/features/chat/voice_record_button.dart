import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 语音录制按钮 —— 长按说话 + 脉冲动画 + 上滑取消。
///
/// 回调：
/// - [onStart]：开始录音
/// - [onCancel]：取消录音（上滑松开）
/// - [onStop]：停止录音，返回是否应发送
/// - [enabled]：是否可用
class VoiceRecordButton extends StatefulWidget {
  final VoidCallback? onStart;
  final VoidCallback? onCancel;
  final VoidCallback? onStop; // 松开发送
  final bool enabled;
  final bool isRecording;

  const VoiceRecordButton({
    super.key,
    this.onStart,
    this.onCancel,
    this.onStop,
    this.enabled = true,
    this.isRecording = false,
  });

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  bool _isPressed = false;
  bool _swipeToCancel = false;

  /// 上滑取消的阈值（像素）。
  static const _cancelSwipeThreshold = -60.0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _onLongPressStart(LongPressStartDetails details) {
    if (!widget.enabled || widget.isRecording) return;
    HapticFeedback.mediumImpact();
    _isPressed = true;
    _swipeToCancel = false;
    _pulseController.repeat(reverse: true);
    widget.onStart?.call();
    setState(() {});
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_isPressed) return;
    final wasCancel = _swipeToCancel;
    _swipeToCancel = details.localOffsetFromOrigin.dy < _cancelSwipeThreshold;
    if (_swipeToCancel != wasCancel) {
      HapticFeedback.selectionClick();
      setState(() {});
    }
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (!_isPressed) return;
    _isPressed = false;
    _pulseController.stop();
    _pulseController.reset();
    final shouldCancel = _swipeToCancel;
    _swipeToCancel = false;
    setState(() {});

    if (shouldCancel) {
      widget.onCancel?.call();
    } else {
      widget.onStop?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final recording = widget.isRecording && _isPressed;

    return GestureDetector(
      onLongPressStart: _onLongPressStart,
      onLongPressMoveUpdate: _onLongPressMoveUpdate,
      onLongPressEnd: _onLongPressEnd,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final pulseValue = _pulseController.isAnimating
              ? _pulseController.value
              : 0.0;
          // 脉冲：内圈 0.85 → 1.05
          final innerScale = recording ? 0.85 + pulseValue * 0.2 : 1.0;
          // 外圈：1.0 → 1.4
          final outerScale = recording ? 1.0 + pulseValue * 0.4 : 1.0;

          // 颜色：正常灰色 / 录音红色 / 取消灰色
          final baseColor = recording
              ? _swipeToCancel
                  ? Colors.grey.shade400
                  : Colors.red
              : _swipeToCancel
                  ? Colors.grey.shade400
                  : Colors.grey.shade500;

          return SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 外圈脉冲环（仅录音时显示）
                if (recording)
                  Transform.scale(
                    scale: outerScale,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _swipeToCancel
                              ? Colors.grey.shade300
                              : Colors.red.withValues(alpha: 0.25),
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
                // 内圈按钮
                Transform.scale(
                  scale: innerScale,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: recording
                          ? baseColor.withValues(alpha: 0.15)
                          : Colors.transparent,
                    ),
                    child: Icon(
                      _recordingIcon(recording),
                      size: 22,
                      color: baseColor,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  IconData _recordingIcon(bool recording) {
    if (recording) {
      return _swipeToCancel ? Icons.close_rounded : Icons.mic_rounded;
    }
    return widget.isRecording ? Icons.mic_rounded : Icons.mic_none_rounded;
  }
}
