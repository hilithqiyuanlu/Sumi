import 'package:flutter/material.dart';

import '../../store/sumi_store.dart';
import '../../theme/app_theme.dart';

/// 弹出 AI 拆分确认面板。
/// 返回 true 表示用户确认添加，false 表示取消。
Future<void> showSplitConfirmSheet(
  BuildContext context,
  SumiStore store,
  List<String> items,
) async {
  final selected = List<bool>.filled(items.length, true);

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(radiusCard)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(s16, s16, s16, s8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 把手
                  Center(
                    child: Container(
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: textTertiary.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: s16),

                  // 标题
                  Text(
                    'AI 已将内容拆分为 ${items.length} 条',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: s4),
                  const Text(
                    '取消勾选不需要的条目后确认添加',
                    style: TextStyle(fontSize: 13, color: textTertiary),
                  ),
                  const SizedBox(height: s12),

                  // 列表
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.45,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: selected[index],
                          onChanged: (v) {
                            setSheetState(() => selected[index] = v ?? false);
                          },
                          title: Text(
                            items[index],
                            style: const TextStyle(fontSize: 14, color: ink),
                          ),
                          activeColor: mintDeep,
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: s16),

                  // 按钮
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: s12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('确认添加'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: s8),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  if (confirmed == true) {
    for (var i = 0; i < items.length; i++) {
      if (selected[i]) {
        store.addUserTodo(items[i]);
      }
    }
  }
}
