import 'package:flutter/material.dart';

import '../../services/local_retrieval_coordinator.dart';
import '../../services/model_package_manager.dart';
import '../../store/sumi_store.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';

class LocalRetrievalPage extends StatelessWidget {
  const LocalRetrievalPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.watchSettings(context);
    final state = store.localRetrievalState;
    final progress = state.totalBytes == 0
        ? 0.0
        : state.downloadedBytes / state.totalBytes;
    final index = state.indexProgress;
    final indexProgress = index.total == 0
        ? 0.0
        : index.completed / index.total;
    final ready = state.packageStatus == LocalModelPackageStatus.ready;
    final busy = switch (state.packageStatus) {
      LocalModelPackageStatus.checking ||
      LocalModelPackageStatus.downloading ||
      LocalModelPackageStatus.verifying => true,
      _ => false,
    };

    return Scaffold(
      backgroundColor: paper,
      appBar: AppBar(title: const Text('本地检索')),
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
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '学习记录只在本机查找',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                SizedBox(height: s6),
                Text(
                  '模型会在设备上理解项目、事项、记忆、信号和历史对话；不会将这些文本上传用于生成向量。',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: s20),
          _Row(label: '模型', value: 'bge-small-zh-v1.5 · ONNX INT8'),
          _Row(label: '状态', value: _statusLabel(state)),
          if (state.version != null) _Row(label: '版本', value: state.version!),
          if (ready)
            _Row(label: '索引版本', value: state.indexVersion ?? '正在安全升级索引'),
          if (busy || state.totalBytes > 0) ...[
            const SizedBox(height: s12),
            LinearProgressIndicator(value: progress == 0 ? null : progress),
            const SizedBox(height: s6),
            Text(
              '${_bytes(state.downloadedBytes)} / ${_bytes(state.totalBytes)}',
              style: const TextStyle(fontSize: 12, color: textTertiary),
            ),
          ],
          if (index.running || index.total > 0) ...[
            const SizedBox(height: s20),
            const Text(
              '建立学习记录索引',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: s8),
            LinearProgressIndicator(
              value: indexProgress == 0 ? null : indexProgress,
            ),
            const SizedBox(height: s6),
            Text(
              index.running
                  ? '${index.completed} / ${index.total}'
                  : (index.message ?? '等待索引'),
              style: const TextStyle(fontSize: 12, color: textTertiary),
            ),
          ],
          if (state.error != null) ...[
            const SizedBox(height: s16),
            Text(
              state.error!,
              style: const TextStyle(fontSize: 13, color: danger),
            ),
          ],
          const SizedBox(height: s24),
          if (!ready)
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () {
                      H.light();
                      store.downloadLocalRetrievalModel();
                    },
              icon: const Icon(Icons.download_outlined, size: iconSmall),
              label: Text(busy ? '正在准备模型' : '下载本地模型'),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => store.recheckLocalRetrievalModel(),
                    icon: const Icon(Icons.verified_outlined, size: iconSmall),
                    label: const Text('重新校验'),
                  ),
                ),
                const SizedBox(width: s12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmDelete(context, store),
                    style: OutlinedButton.styleFrom(foregroundColor: danger),
                    icon: const Icon(Icons.delete_outline, size: iconSmall),
                    label: const Text('删除模型'),
                  ),
                ),
              ],
            ),
          if (busy || index.running)
            TextButton(
              onPressed: store.cancelLocalRetrievalWork,
              child: const Text('暂停当前任务'),
            ),
        ],
      ),
    );
  }

  static String _statusLabel(LocalRetrievalState state) =>
      switch (state.packageStatus) {
        LocalModelPackageStatus.unavailable => '尚未下载',
        LocalModelPackageStatus.checking => '正在检查模型包',
        LocalModelPackageStatus.downloading => '正在下载',
        LocalModelPackageStatus.verifying => '正在校验',
        LocalModelPackageStatus.ready => '已就绪',
        LocalModelPackageStatus.failed => '不可用',
      };

  static String _bytes(int value) => value < 1024 * 1024
      ? '${(value / 1024).toStringAsFixed(0)} KB'
      : '${(value / 1024 / 1024).toStringAsFixed(1)} MB';

  Future<void> _confirmDelete(BuildContext context, AppStore store) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除本地模型？'),
        content: const Text('这会删除模型和本地检索索引，不会删除项目、事项、聊天或记忆。'),
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
    );
    if (confirmed == true) await store.deleteLocalRetrievalModel();
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});

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
