import 'package:flutter/material.dart';

import '../../store/sumi_store.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';

class SettingsBody extends StatefulWidget {
  const SettingsBody({super.key});

  @override
  State<SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<SettingsBody> {
  bool _deepseekVisible = false;
  bool _tavilyVisible = false;

  // Sumi 记忆
  final _memoryController = TextEditingController();
  final _memoryFocusNode = FocusNode();
  bool _memoryLoaded = false;
  bool _memorySaving = false;
  bool _isEditingMemory = false;

  @override
  void initState() {
    super.initState();
    _loadMemory();
  }

  @override
  void dispose() {
    _memoryController.dispose();
    _memoryFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadMemory() async {
    final store = SumiScope.read(context);
    final content = await store.readMemory();
    if (!mounted) return;
    _memoryController.text = content;
    setState(() => _memoryLoaded = true);
  }

  Future<void> _saveMemory() async {
    H.click();
    setState(() => _memorySaving = true);
    final store = SumiScope.read(context);
    await store.writeMemory(_memoryController.text);
    if (!mounted) return;
    setState(() {
      _memorySaving = false;
      _isEditingMemory = false;
    });
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusCard)),
        ),
        title: const Text('清空记忆', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: const Text('确定要清空 Sumi 的全部记忆吗？此操作不可撤销。', style: TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('清空', style: TextStyle(color: danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      H.medium();
      _memoryController.clear();
      final store = SumiScope.read(context);
      await store.writeMemory('');
      if (!mounted) return;
      setState(() => _isEditingMemory = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('记忆已清空'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _memoryPreview(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '暂无记忆';
    final lines = trimmed.split('\n');
    final firstLines = lines.take(3).join('\n');
    if (lines.length > 3 || trimmed.length > 80) {
      return '${firstLines.substring(0, firstLines.length.clamp(0, 80))}…';
    }
    return firstLines;
  }

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.watch(context);

    final topPadding = MediaQuery.of(context).padding.top;
    return ListView(
      padding: EdgeInsets.fromLTRB(s16, topPadding + 56, s16, s8),
      children: [
        _buildCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader('API 密钥'),
              const SizedBox(height: s12),
              _apiKeyTile(
                label: 'DeepSeek API Key',
                currentValue: store.appSettings.deepseekApiKey,
                visible: _deepseekVisible,
                onToggle: () =>
                    setState(() => _deepseekVisible = !_deepseekVisible),
                onSave: (v) => store.updateDeepseekApiKey(v),
              ),
              const Divider(height: 1),
              _apiKeyTile(
                label: 'Tavily API Key',
                currentValue: store.appSettings.tavilyApiKey,
                visible: _tavilyVisible,
                onToggle: () =>
                    setState(() => _tavilyVisible = !_tavilyVisible),
                onSave: (v) => store.updateTavilyApiKey(v),
              ),
            ],
          ),
        ),
        const SizedBox(height: s24),
        _sectionHeader('Sumi 记忆'),
        const SizedBox(height: s12),
        _buildMemoryCard(store),
        const SizedBox(height: s24),
        _sectionHeader('思考模式'),
        const SizedBox(height: s12),
        _buildCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('深度思考',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            subtitle: const Text('开启后 Sumi 会在回复前展示推理过程',
                style: TextStyle(fontSize: 12)),
            trailing: Switch(
              value: store.thinkingEnabled,
              onChanged: (v) { H.click(); store.setThinkingEnabled(v); },
            ),
          ),
        ),
        const SizedBox(height: s24),
        _sectionHeader('开发者'),
        const SizedBox(height: s12),
        _buildCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('披露全部月卡',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            subtitle: const Text('关闭锁卡，显示所有月份的规划内容',
                style: TextStyle(fontSize: 12)),
            trailing: Switch(
              value: store.appSettings.showAllMonthCards,
              onChanged: (v) { H.click(); store.setShowAllMonthCards(v); },
            ),
          ),
        ),
        const SizedBox(height: s24),
        _sectionHeader('数据管理'),
        const SizedBox(height: s12),
        Center(
          child: FilledButton.icon(
            onPressed: () { H.medium(); _confirmClearData(context, store); },
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('清除数据',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
            style: FilledButton.styleFrom(
              backgroundColor: danger,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: s20, vertical: s10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radiusPill),
              ),
            ),
          ),
        ),
        const SizedBox(height: s24),
        Center(
          child: Text(
            'Sumi · v1.0.0',
            style: TextStyle(fontSize: 12, color: textTertiary),
          ),
        ),
        const SizedBox(height: s24),
      ],
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: s8),
      padding: const EdgeInsets.all(s16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radiusCard),
        boxShadow: const [...shadow1],
      ),
      child: child,
    );
  }

  Widget _buildMemoryCard(SumiStore store) {
    if (!_memoryLoaded) {
      return _buildCard(
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(s24),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isEditingMemory) ...[
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: line),
                borderRadius: BorderRadius.circular(radiusPanel),
              ),
              child: TextField(
                controller: _memoryController,
                focusNode: _memoryFocusNode,
                autofocus: true,
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
                  onPressed: _memorySaving ? null : _saveMemory,
                  child: const Text('保存'),
                ),
                const SizedBox(width: s8),
                TextButton(
                  onPressed: _clearMemory,
                  child: Text(
                    '清空记忆',
                    style: TextStyle(color: danger),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _isEditingMemory = false),
                  child: const Text('取消'),
                ),
              ],
            ),
          ] else ...[
            Text(
              _memoryPreview(_memoryController.text),
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: _memoryController.text.trim().isEmpty
                    ? textTertiary
                    : ink,
              ),
            ),
            const SizedBox(height: s12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  H.light();
                  setState(() => _isEditingMemory = true);
                  // 延迟一帧确保 TextField 已挂载再聚焦
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _memoryFocusNode.requestFocus();
                  });
                },
                child: const Text('编辑'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: textTertiary,
      ),
    );
  }

  Widget _apiKeyTile({
    required String label,
    required String currentValue,
    required bool visible,
    required VoidCallback onToggle,
    required ValueChanged<String> onSave,
  }) {
    final hasKey = currentValue.isNotEmpty;
    final display = hasKey
        ? (visible ? currentValue : '••••••••${currentValue.length > 4 ? currentValue.substring(currentValue.length - 4) : currentValue}')
        : '未设置';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: Text(display, style: const TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasKey)
            IconButton(
              icon: Icon(
                visible ? Icons.visibility_off : Icons.visibility,
                size: iconSmall,
              ),
              onPressed: onToggle,
            ),
          IconButton(
            icon: Icon(Icons.edit, size: iconSmall),
            onPressed: () => _editApiKey(
              context, label, currentValue, onSave),
          ),
        ],
      ),
    );
  }

  void _editApiKey(BuildContext context, String label,
      String currentValue, ValueChanged<String> onSave) {
    final controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(radiusCard)),
          ),
          title: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '粘贴 API Key',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                onSave(controller.text.trim());
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    ).then((_) => controller.dispose());
  }

  void _confirmClearData(BuildContext context, SumiStore store) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(radiusCard)),
          ),
          title: const Text('清除所有数据', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          content: const Text(
            '此操作将删除所有项目、月卡、事项及偏好设置。\n\n此操作不可恢复。',
            style: TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: danger,
                  foregroundColor: Colors.white),
              onPressed: () {
                store.clearAllData(keepSecrets: true);
                Navigator.pop(ctx);
              },
              child: const Text('确认清除'),
            ),
          ],
        );
      },
    );
  }
}
