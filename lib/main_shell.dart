import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'features/chat/chat_page.dart';
import 'features/settings/settings_page.dart';
import 'features/todos/todos_page.dart';
import 'sumi_scope.dart';

/// 应用主壳 —— 3 Tab 底部导航。
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 1; // 默认首页仍是"事项"

  static const _pages = <Widget>[
    ChatPage(),
    TodosPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        behavior: HitTestBehavior.translucent,
        child: IndexedStack(
          index: _tab,
          children: _pages,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          HapticFeedback.selectionClick();
          if (i == _tab) {
            if (i == 1) {
              // 事项 Tab — 二次点击：收起月视图 / 回到当日
              SumiScope.read(context).triggerNavigateToToday();
            }
            return;
          }
          // 离开 Sumi Tab 时清理空对话
          if (_tab == 0) {
            SumiScope.read(context).cleanupEmptyConversation();
          }
          setState(() => _tab = i);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.psychology_outlined),
            selectedIcon: Icon(Icons.psychology_rounded),
            label: 'Sumi',
          ),
          NavigationDestination(
            icon: Icon(Icons.check_circle_outline),
            selectedIcon: Icon(Icons.check_circle_rounded),
            label: '事项',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
