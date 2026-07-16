import 'package:flutter/material.dart';

import '../../services/chat_tool_registry.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';

class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.watchSettings(context);
    final enabled = store.enabledTools.toSet();
    const groups = ['读取与检索', '创建与执行'];
    return Scaffold(
      backgroundColor: paper,
      appBar: AppBar(title: const Text('工具')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(s16, s8, s16, s24),
        children: [
          const Text(
            '关闭后，Sumi 不会看到或执行该工具。已开始的计时和项目生成不会中断。',
            style: TextStyle(fontSize: 13, height: 1.5, color: textTertiary),
          ),
          const SizedBox(height: s20),
          for (final group in groups) ...[
            Text(
              group,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textTertiary,
              ),
            ),
            const SizedBox(height: s8),
            ...ChatToolRegistry.definitions
                .where((tool) => tool.group == group)
                .map(
                  (tool) => Container(
                    margin: const EdgeInsets.only(bottom: s8),
                    padding: const EdgeInsets.fromLTRB(s14, s10, s8, s10),
                    decoration: BoxDecoration(
                      border: Border.all(color: surfaceChip),
                      borderRadius: BorderRadius.circular(radius8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tool.label,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: s2),
                              Text(
                                tool.description,
                                style: const TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: enabled.contains(tool.name),
                          onChanged: (value) {
                            H.click();
                            final next = {...enabled};
                            if (value) {
                              next.add(tool.name);
                            } else {
                              next.remove(tool.name);
                            }
                            store.updateEnabledTools(next);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: s12),
          ],
        ],
      ),
    );
  }
}
