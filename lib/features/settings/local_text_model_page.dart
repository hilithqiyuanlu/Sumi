import 'package:flutter/material.dart';

import '../../services/local_text_generation_coordinator.dart';
import '../../store/sumi_store.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';

class LocalTextModelPage extends StatelessWidget {
  const LocalTextModelPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.watchSettings(context);
    final state = store.localTextModelState;
    final busy = switch (state.status) {
      LocalTextModelStatus.checking ||
      LocalTextModelStatus.downloading ||
      LocalTextModelStatus.loading => true,
      _ => false,
    };
    final progress = state.totalBytes == 0
        ? 0.0
        : state.receivedBytes / state.totalBytes;
    return Scaffold(
      backgroundColor: paper,
      appBar: AppBar(title: const Text('本地生成')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(s16, s8, s16, s24),
        children: [
          Container(
            padding: const EdgeInsets.all(s16),
            decoration: BoxDecoration(
              color: primary50,
              borderRadius: BorderRadius.circular(radius8),
              border: Border.all(color: primary100),
            ),
            child: const Text(
              'Qwen3.5-0.8B 只处理短结构化任务。聊天仍使用 Flash，项目规划仍使用 Pro。',
              style: TextStyle(fontSize: 13, height: 1.5, color: textTertiary),
            ),
          ),
          const SizedBox(height: s20),
          _Info(label: '模型', value: 'Qwen3.5-0.8B · Q4_K_M'),
          _Info(label: '大小', value: '约 533 MB'),
          _Info(label: '状态', value: _label(state.status)),
          if (state.version != null) _Info(label: '版本', value: state.version!),
          if (busy) ...[
            const SizedBox(height: s16),
            LinearProgressIndicator(value: progress == 0 ? null : progress),
            const SizedBox(height: s6),
            Text(
              '${(state.receivedBytes / 1024 / 1024).toStringAsFixed(1)} / ${(state.totalBytes / 1024 / 1024).toStringAsFixed(1)} MB',
              style: const TextStyle(fontSize: 12, color: textTertiary),
            ),
          ],
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(top: s16),
              child: Text(state.error!, style: const TextStyle(color: danger)),
            ),
          const SizedBox(height: s24),
          if (state.status != LocalTextModelStatus.ready)
            FilledButton.icon(
              onPressed: busy ? null : store.downloadLocalTextModel,
              icon: const Icon(Icons.download_outlined, size: iconSmall),
              label: Text(busy ? '正在准备模型' : '下载本地模型'),
            )
          else
            OutlinedButton.icon(
              onPressed: () => _confirmDelete(context, store),
              icon: const Icon(Icons.delete_outline, size: iconSmall),
              label: const Text('删除模型'),
            ),
        ],
      ),
    );
  }

  static String _label(LocalTextModelStatus status) => switch (status) {
    LocalTextModelStatus.unavailable => '尚未下载',
    LocalTextModelStatus.checking => '正在检查',
    LocalTextModelStatus.downloading => '正在下载',
    LocalTextModelStatus.loading => '正在加载',
    LocalTextModelStatus.ready => '已就绪',
    LocalTextModelStatus.failed => '不可用',
  };
  Future<void> _confirmDelete(BuildContext context, AppStore store) async {
    if (await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('删除本地模型？'),
            content: const Text('不会删除项目、事项、聊天或记忆。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ==
        true) {
      await store.deleteLocalTextModel();
    }
  }
}

class _Info extends StatelessWidget {
  final String label;
  final String value;
  const _Info({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: s8),
    child: Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: textTertiary),
          ),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 14, color: ink)),
        ),
      ],
    ),
  );
}
