import 'package:flutter/material.dart';

import '../../store/sumi_store.dart';
import '../../theme/app_theme.dart';

/// Sumi 工具面板（扳手菜单）—— MEMORY.md 编辑器 + 思考模式开关。
class SumiToolsSheet extends StatefulWidget {
  final SumiStore store;

  const SumiToolsSheet({required this.store, super.key});

  /// 显示工具面板。
  static Future<void> show(BuildContext context, SumiStore store) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(radiusCardHeader)),
      ),
      builder: (_) => SumiToolsSheet(store: store),
    );
  }

  @override
  State<SumiToolsSheet> createState() => _SumiToolsSheetState();
}

class _SumiToolsSheetState extends State<SumiToolsSheet> {
  final _memoryController = TextEditingController();
  bool _memoryLoaded = false;
  bool _memorySaving = false;

  @override
  void initState() {
    super.initState();
    _loadMemory();
  }

  Future<void> _loadMemory() async {
    final content = await widget.store.readMemory();
    if (!mounted) return;
    _memoryController.text = content;
    setState(() => _memoryLoaded = true);
  }

  Future<void> _saveMemory() async {
    setState(() => _memorySaving = true);
    await widget.store.writeMemory(_memoryController.text);
    if (!mounted) return;
    setState(() => _memorySaving = false);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('记忆已保存'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _clearMemory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空记忆'),
        content: const Text('确定要清空 Sumi 的全部记忆吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('清空', style: TextStyle(color: Colors.red.shade400)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _memoryController.clear();
      await widget.store.writeMemory('');
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('记忆已清空'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    _memoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 拖拽把手
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: s16),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: textTertiary.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // ---- Section: Sumi 记忆 ----
              const Text(
                'Sumi 记忆',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
              const SizedBox(height: s4),
              Text(
                '编辑 Sumi 的 MEMORY.md，AI 可通过 read_memory 工具读取。',
                style: TextStyle(fontSize: 13, color: textTertiary),
              ),
              const SizedBox(height: s12),
              if (!_memoryLoaded)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(s24),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: line),
                    borderRadius: BorderRadius.circular(radiusPanel),
                  ),
                  child: TextField(
                    controller: _memoryController,
                    maxLines: 12,
                    minLines: 6,
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      height: 1.5,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(s12),
                    ),
                  ),
                ),
              const SizedBox(height: s12),
              Row(
                children: [
                  FilledButton(
                    onPressed:
                        (_memoryLoaded && !_memorySaving) ? _saveMemory : null,
                    child: const Text('保存'),
                  ),
                  const SizedBox(width: s8),
                  TextButton(
                    onPressed: _memoryLoaded ? _clearMemory : null,
                    child: Text(
                      '清空记忆',
                      style: TextStyle(color: Colors.red.shade400),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: s24),
              const Divider(),
              const SizedBox(height: s16),

              // ---- Section: 思考模式 ----
              const Text(
                '思考模式',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
              const SizedBox(height: s4),
              Text(
                '开启后 Sumi 会先思考再回复，回复质量更高但速度较慢。',
                style: TextStyle(fontSize: 13, color: textTertiary),
              ),
              const SizedBox(height: s8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('深度思考'),
                subtitle: Text(
                  store.thinkingEnabled ? '已开启' : '已关闭',
                  style: TextStyle(fontSize: 12, color: textTertiary),
                ),
                value: store.thinkingEnabled,
                activeTrackColor: mintDeep.withValues(alpha: 0.4),
                onChanged: (v) => store.setThinkingEnabled(v),
              ),

              // 底部留白
              SizedBox(
                  height: MediaQuery.of(context).padding.bottom + s24),
            ],
          ),
        );
      },
    );
  }
}
