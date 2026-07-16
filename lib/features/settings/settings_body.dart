import 'package:flutter/material.dart';

import '../../store/sumi_store.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';
import 'signal_log_page.dart';
import 'model_router_metrics_page.dart';
import 'local_retrieval_page.dart';
import 'local_text_model_page.dart';

class SettingsBody extends StatefulWidget {
  const SettingsBody({super.key});

  @override
  State<SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<SettingsBody> {
  bool _deepseekVisible = false;
  bool _tavilyVisible = false;

  // 07 轮：移除内联编辑，改为导航到独立编辑器页面

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.watchSettings(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(s16, s16, s16, s8),
      children: [
        _sectionHeader('API 密钥'),
        const SizedBox(height: s12),
        _buildCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
        _sectionHeader('本地智能'),
        const SizedBox(height: s12),
        _buildCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              '本地生成',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: const Text('用设备模型处理短任务', style: TextStyle(fontSize: 12)),
            trailing: const Icon(
              Icons.chevron_right,
              size: iconSection,
              color: textTertiary,
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LocalTextModelPage()),
            ),
          ),
        ),
        const SizedBox(height: s12),
        _buildCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              '本地检索',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: const Text(
              '在设备上查找你的学习记录',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              size: iconSection,
              color: textTertiary,
            ),
            onTap: () {
              H.light();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LocalRetrievalPage()),
              );
            },
          ),
        ),
        const SizedBox(height: s24),
        _sectionHeader('思考模式'),
        const SizedBox(height: s12),
        _buildCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              '深度思考',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: const Text(
              '开启后提升复杂问题处理能力，不展示内部推理',
              style: TextStyle(fontSize: 12),
            ),
            trailing: Switch(
              value: store.thinkingEnabled,
              onChanged: (v) {
                H.click();
                store.setThinkingEnabled(v);
              },
            ),
          ),
        ),
        const SizedBox(height: s24),
        _sectionHeader('开发者'),
        const SizedBox(height: s12),
        _buildCard(
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '披露全部月卡',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                subtitle: const Text(
                  '关闭锁卡，显示所有月份的规划内容',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: Switch(
                  value: store.appSettings.showAllMonthCards,
                  onChanged: (v) {
                    H.click();
                    store.setShowAllMonthCards(v);
                  },
                ),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '模型路由诊断',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: ink,
                  ),
                ),
                subtitle: const Text(
                  '查看近 7 天的本地调用汇总，不包含对话内容',
                  style: TextStyle(fontSize: 12, color: textSecondary),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  size: iconSection,
                  color: textTertiary,
                ),
                onTap: () {
                  H.light();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ModelRouterMetricsPage(),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '信号日志',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                subtitle: const Text(
                  '查看用户行为信号记录',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  size: iconSection,
                  color: textTertiary,
                ),
                onTap: () {
                  H.light();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SignalLogPage()),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: s24),
        _sectionHeader('数据管理'),
        const SizedBox(height: s12),
        Center(
          child: FilledButton.icon(
            onPressed: () {
              H.medium();
              _confirmClearData(context, store);
            },
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text(
              '清除数据',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: danger,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: s20,
                vertical: s10,
              ),
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
        ? (visible
              ? currentValue
              : '••••••••${currentValue.length > 4 ? currentValue.substring(currentValue.length - 4) : currentValue}')
        : '未设置';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
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
            onPressed: () => _editApiKey(context, label, currentValue, onSave),
          ),
        ],
      ),
    );
  }

  void _editApiKey(
    BuildContext context,
    String label,
    String currentValue,
    ValueChanged<String> onSave,
  ) {
    final controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(radiusCard)),
          ),
          title: Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '粘贴 API Key'),
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
          title: const Text(
            '清除所有数据',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
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
                foregroundColor: Colors.white,
              ),
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
