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
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: s16, vertical: s8),
        children: [
          // ── API Key 区 ──
          _sectionHeader('API 密钥'),
          const SizedBox(height: s8),

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

          const SizedBox(height: s24),

          // ── 模型区 ──
          _sectionHeader('模型配置'),
          const SizedBox(height: s8),
          _readOnlyTile('规划模型', store.appSettings.plannerModel),
          const Divider(height: 1),
          _readOnlyTile('默认模型', store.appSettings.defaultModel),

          const SizedBox(height: s24),

          // ── 数据区 ──
          _sectionHeader('数据管理'),
          const SizedBox(height: s8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_forever_rounded,
                color: Colors.red.shade400),
            title: Text('清除所有数据',
                style: TextStyle(color: Colors.red.shade400)),
            subtitle: const Text(
              '删除项目、月卡、事项及偏好，保留 API 密钥',
              style: TextStyle(fontSize: 12),
            ),
            trailing: Icon(Icons.chevron_right_rounded,
                color: Colors.red.shade400),
            onTap: () => _confirmClearData(context, store),
          ),

          const SizedBox(height: s24),

          // ── 版本信息 ──
          Center(
            child: Text(
              'Sumi（米糖）· v1.0.0',
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
                visible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                size: iconSmall,
              ),
              onPressed: onToggle,
            ),
          IconButton(
            icon: Icon(Icons.edit_rounded, size: iconSmall),
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

  Widget _readOnlyTile(String label, String value) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      trailing: Text(value,
          style: const TextStyle(fontSize: 13, color: textTertiary)),
    );
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
                  backgroundColor: Colors.red.shade400),
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
