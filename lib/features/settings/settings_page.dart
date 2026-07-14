import 'package:flutter/material.dart';

import '../../store/sumi_store.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';

/// 设置页 —— API Key 管理 + Clear Data。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _deepseekVisible = false;
  bool _tavilyVisible = false;

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.watch(context);

    return Scaffold(
      appBar: AppBar(
        title: null,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: s16, vertical: s8),
        children: [
          // ── API Key 区 ──
          Container(
            margin: const EdgeInsets.only(bottom: s8),
            padding: const EdgeInsets.all(s16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(radiusCard),
              boxShadow: const [...shadow1],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader('API 密钥'),
                const SizedBox(height: s12),

                // DeepSeek
                _apiKeyTile(
                  label: 'DeepSeek API Key',
                  currentValue: store.appSettings.deepseekApiKey,
                  visible: _deepseekVisible,
                  onToggle: () =>
                      setState(() => _deepseekVisible = !_deepseekVisible),
                  onSave: (v) => store.updateDeepseekApiKey(v),
                ),
                const Divider(height: 1),

                // Tavily
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

          // ── 开发者区 ──
          _sectionHeader('开发者'),
          const SizedBox(height: s8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('披露全部月卡',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            subtitle: const Text('关闭锁卡，显示所有月份的规划内容',
                style: TextStyle(fontSize: 12)),
            trailing: Switch(
              value: store.appSettings.showAllMonthCards,
              onChanged: (v) => store.setShowAllMonthCards(v),
            ),
          ),

          const SizedBox(height: s24),

          // ── 数据区 ──
          _sectionHeader('数据管理'),
          const SizedBox(height: s8),
          Center(
            child: FilledButton.icon(
              onPressed: () => _confirmClearData(context, store),
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

          // ── 版本信息 ──
          Center(
            child: Text(
              'Sumi · v1.0.0',
              style: TextStyle(fontSize: 12, color: textTertiary),
            ),
          ),
          const SizedBox(height: s24),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // helpers
  // -------------------------------------------------------------------------

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
          title: Text(label),
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
          title: const Text('清除所有数据'),
          content: const Text(
            '此操作将删除所有项目、月卡、事项及偏好设置。\n\nAPI 密钥将被保留。\n\n此操作不可恢复。',
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
