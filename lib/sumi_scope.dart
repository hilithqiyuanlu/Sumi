import 'package:flutter/material.dart';

import 'store/sumi_store.dart';

class SumiScope extends StatelessWidget {
  final AppStore store;
  final Widget child;

  const SumiScope({required this.store, required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return _AppStoreScope(
      store: store,
      child: _TodoScope(
        controller: store.todoController,
        child: _ProjectScope(
          controller: store.projectController,
          child: _SettingsScope(
            controller: store.settingsController,
            child: _SelectionScope(
              controller: store.selection,
              child: _MilestoneScope(
                controller: store.milestoneController,
                child: _DailyReflectionScope(
                  controller: store.dailyReflectionController,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static AppStore read(BuildContext context) {
    final scope =
        context
                .getElementForInheritedWidgetOfExactType<_AppStoreScope>()
                ?.widget
            as _AppStoreScope?;
    assert(scope != null, 'SumiScope.read: 未找到 SumiScope');
    return scope!.store;
  }

  static AppStore watchTodos(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<_TodoScope>();
    return read(context);
  }

  static AppStore watchProjects(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<_ProjectScope>();
    return read(context);
  }

  static AppStore watchSettings(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<_SettingsScope>();
    return read(context);
  }

  static AppStore watchSelection(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<_SelectionScope>();
    return read(context);
  }

  static AppStore watchMilestones(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<_MilestoneScope>();
    return read(context);
  }

  static AppStore watchDailyReflections(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<_DailyReflectionScope>();
    return read(context);
  }
}

class _AppStoreScope extends InheritedWidget {
  final AppStore store;

  const _AppStoreScope({required this.store, required super.child});

  @override
  bool updateShouldNotify(_AppStoreScope oldWidget) => oldWidget.store != store;
}

class _TodoScope extends InheritedNotifier<TodoController> {
  const _TodoScope({required TodoController controller, required super.child})
    : super(notifier: controller);
}

class _ProjectScope extends InheritedNotifier<ProjectController> {
  const _ProjectScope({
    required ProjectController controller,
    required super.child,
  }) : super(notifier: controller);
}

class _SettingsScope extends InheritedNotifier<SettingsController> {
  const _SettingsScope({
    required SettingsController controller,
    required super.child,
  }) : super(notifier: controller);
}

class _SelectionScope extends InheritedNotifier<SelectionController> {
  const _SelectionScope({
    required SelectionController controller,
    required super.child,
  }) : super(notifier: controller);
}

class _MilestoneScope extends InheritedNotifier<MilestoneController> {
  const _MilestoneScope({
    required MilestoneController controller,
    required super.child,
  }) : super(notifier: controller);
}

class _DailyReflectionScope
    extends InheritedNotifier<DailyReflectionController> {
  const _DailyReflectionScope({
    required DailyReflectionController controller,
    required super.child,
  }) : super(notifier: controller);
}
