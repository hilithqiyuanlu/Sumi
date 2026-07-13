import 'package:flutter/material.dart';

import 'store/sumi_store.dart';

/// 通过 InheritedNotifier 向子树注入 SumiStore。
class SumiScope extends InheritedNotifier<SumiStore> {
  const SumiScope({
    required SumiStore store,
    required super.child,
    super.key,
  }) : super(notifier: store);

  /// 订阅 —— store 变化时触发重建。
  static SumiStore watch(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<SumiScope>();
    assert(scope != null, 'SumiScope.watch: 未找到 SumiScope');
    return scope!.notifier!;
  }

  /// 读取不订阅 —— 不触发重建。
  static SumiStore read(BuildContext context) {
    final scope = context
        .getElementForInheritedWidgetOfExactType<SumiScope>()
        ?.widget as SumiScope?;
    assert(scope != null, 'SumiScope.read: 未找到 SumiScope');
    return scope!.notifier!;
  }
}
