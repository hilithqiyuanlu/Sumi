import 'package:flutter/material.dart';

import '../../store/sumi_store.dart';
import '../../theme/app_theme.dart';
import '../shared/drag_handle.dart';

/// 会话列表底部 Sheet。
class ConversationList extends StatelessWidget {
  final SumiStore store;

  const ConversationList({required this.store, super.key});

  /// 显示会话列表。
  static Future<void> show(BuildContext context, SumiStore store) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(radiusCardHeader)),
      ),
      builder: (_) => ConversationList(store: store),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final conversations = store.conversations;

        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                // 拖拽把手
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: s12),
                  child: DragHandle(),
                ),
                // 标题栏
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: s16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '对话历史',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          store.createConversation();
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('新建'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // 列表
                Expanded(
                  child: conversations.isEmpty
                      ? Center(
                          child: Text(
                            '还没有对话，点击新建开始吧',
                            style: TextStyle(
                                fontSize: 14, color: textTertiary),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: conversations.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, indent: s16),
                          itemBuilder: (context, index) {
                            final conv = conversations[index];
                            final isActive =
                                conv.id == store.currentConversationId;

                            return ListTile(
                              selected: isActive,
                              selectedTileColor:
                                  mint.withValues(alpha: 0.2),
                              title: Text(
                                conv.title.isNotEmpty ? conv.title : '新对话',
                                style: TextStyle(
                                  fontWeight: isActive
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                              subtitle: Text(
                                _formatTime(conv.updatedAt),
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: isActive
                                  ? Icon(Icons.chat_bubble_outline,
                                      size: 18, color: mintDeep)
                                  : null,
                              onTap: () {
                                Navigator.pop(context);
                                if (!isActive) {
                                  store.switchConversation(conv.id);
                                }
                              },
                              onLongPress: () {
                                _showDeleteDialog(
                                    context, conv.id, conv.title);
                              },
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeleteDialog(BuildContext context, String id, String title) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除对话'),
        content: Text('确定删除「${title.isNotEmpty ? title : "新对话"}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              store.deleteConversation(id);
            },
            child:
                Text('删除', style: TextStyle(color: danger)),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${dt.month}/${dt.day}';
  }
}
