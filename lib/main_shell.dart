import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'features/chat/chat_page.dart';
import 'features/settings/settings_page.dart';
import 'features/todos/todos_page.dart';
import 'sumi_scope.dart';
import 'theme/app_theme.dart';

/// 应用主壳 —— 3 Tab 底部导航（自定义实现，匹配 Sumi Design System）。
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 1; // 默认首页是"事项"

  static const _pages = <Widget>[
    ChatPage(),
    TodosPage(),
    SettingsPage(),
  ];

  static const _navItems = [
    _NavItemData(
      icon: Icons.auto_awesome,
      activeIcon: Icons.auto_awesome,
      label: 'Sumi',
    ),
    _NavItemData(
      icon: Icons.circle_outlined,
      activeIcon: Icons.check_small,
      label: '事项',
    ),
    _NavItemData(
      icon: Icons.tune,
      activeIcon: Icons.tune,
      label: '设置',
    ),
  ];

  void _onTabTap(int index) {
    HapticFeedback.selectionClick();
    if (index == _tab) {
      if (index == 1) {
        // 事项 Tab — 二次点击：收起月视图 / 回到当日
        SumiScope.read(context).triggerNavigateToToday();
      }
      return;
    }
    // 离开 Sumi Tab 时清理空对话
    if (_tab == 0) {
      SumiScope.read(context).cleanupEmptyConversation();
    }
    setState(() => _tab = index);
  }

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
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: paper,
          border: Border(
            top: BorderSide(color: line.withValues(alpha: 0.5)),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(top: s4, bottom: s4),
            child: Row(
              children: List.generate(_navItems.length, (index) {
                final item = _navItems[index];
                final active = index == _tab;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _onTabTap(index),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: active ? primary100 : Colors.transparent,
                            borderRadius: BorderRadius.circular(radius12),
                          ),
                          child: Icon(
                            active ? item.activeIcon : item.icon,
                            size: iconMedium,
                            color: active ? primary700 : textTertiary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                active ? FontWeight.w500 : FontWeight.w400,
                            color: active ? primary700 : textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItemData {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavItemData({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
