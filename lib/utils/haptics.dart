import 'dart:async';

import 'package:flutter/services.dart';

/// 统一触觉反馈工具，充分利用 iPhone 线性马达。
///
/// [H.click]  清脆点击 — 按钮、导航、开关切换（mediumImpact，升级 Flutter 3.7+ 后改为 rigidImpact）
/// [H.light]  轻交互 — chip 打开、面板弹出、滚动 tick（lightImpact）
/// [H.medium] 重要操作 — 长按触发、拖拽、删除、流式结束（mediumImpact）
/// [H.heavy]  重大事件 — 规划完成、严重错误（heavyImpact）
/// [H.tick]   滚轮 tick — 连续选择器（selectionClick，极少用）
/// [H.success] 成功节奏 — medium + 100ms 后 light
/// [H.error]   错误节奏 — 两次 medium，间隔 150ms
sealed class H {
  H._();

  static void click() => HapticFeedback.mediumImpact();
  static void light() => HapticFeedback.lightImpact();
  static void medium() => HapticFeedback.mediumImpact();
  static void heavy() => HapticFeedback.heavyImpact();
  static void tick() => HapticFeedback.selectionClick();

  static void success() {
    HapticFeedback.mediumImpact();
    Future.delayed(
      const Duration(milliseconds: 100),
      HapticFeedback.lightImpact,
    );
  }

  static void error() {
    HapticFeedback.mediumImpact();
    Future.delayed(
      const Duration(milliseconds: 150),
      HapticFeedback.mediumImpact,
    );
  }
}
