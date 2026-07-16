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
          const _LocalIntro(),
          const SizedBox(height: s24),
          const _SectionLabel('模型状态'),
          const SizedBox(height: s8),
          _ModelStatusCard(state: state, ready: ready, busy: busy),
          if (busy || state.totalBytes > 0) ...[
            const SizedBox(height: s16),
            _ProgressPanel(
              title: _statusLabel(state),
              value: progress == 0 ? null : progress,
              detail:
                  '${_bytes(state.downloadedBytes)} / ${_bytes(state.totalBytes)}',
            ),
          ],
          if (index.running || index.total > 0) ...[
            const SizedBox(height: s16),
            _ProgressPanel(
              title: '建立学习记录索引',
              value: indexProgress == 0 ? null : indexProgress,
              detail: index.running
                  ? '${index.completed} / ${index.total}'
                  : (index.message ?? '等待索引'),
            ),
          ],
          if (state.error != null) ...[
            const SizedBox(height: s16),
            Container(
              padding: const EdgeInsets.all(s12),
              decoration: BoxDecoration(
                color: error50,
                borderRadius: BorderRadius.circular(radius8),
                border: Border.all(color: error100),
              ),
              child: Text(
                state.error!,
                style: const TextStyle(fontSize: 13, color: danger),
              ),
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
            TextButton.icon(
              onPressed: store.cancelLocalRetrievalWork,
              icon: const Icon(Icons.pause_circle_outline, size: iconSmall),
              label: const Text('暂停当前任务'),
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

class _LocalIntro extends StatelessWidget {
  const _LocalIntro();

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: primary50,
          borderRadius: BorderRadius.circular(radius12),
        ),
        child: const Icon(Icons.manage_search, color: primary500),
      ),
      const SizedBox(width: s12),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '学习记录只在本机查找',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: s4),
            Text(
              '项目、事项、记忆、信号和历史对话不会被上传用于建立索引。',
              style: TextStyle(fontSize: 13, height: 1.45, color: textTertiary),
            ),
          ],
        ),
      ),
    ],
  );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: textTertiary,
    ),
  );
}

class _ModelStatusCard extends StatelessWidget {
  final LocalRetrievalState state;
  final bool ready;
  final bool busy;

  const _ModelStatusCard({
    required this.state,
    required this.ready,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(s16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius8),
      border: Border.all(color: line),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Icon(
              ready
                  ? Icons.verified_outlined
                  : busy
                  ? Icons.downloading_outlined
                  : Icons.download_outlined,
              size: iconMedium,
              color: ready ? success500 : primary500,
            ),
            const SizedBox(width: s8),
            Expanded(
              child: Text(
                LocalRetrievalPage._statusLabel(state),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: s12),
        const _Row(label: '模型', value: 'bge-small-zh-v1.5 · ONNX INT8'),
        if (state.version != null) _Row(label: '版本', value: state.version!),
        if (ready) _Row(label: '索引', value: state.indexVersion ?? '正在安全升级索引'),
      ],
    ),
  );
}

class _ProgressPanel extends StatelessWidget {
  final String title;
  final double? value;
  final String detail;

  const _ProgressPanel({
    required this.title,
    required this.value,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(s12),
    decoration: BoxDecoration(
      color: surfaceAlt,
      borderRadius: BorderRadius.circular(radius8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: s10),
        LinearProgressIndicator(value: value),
        const SizedBox(height: s8),
        Text(detail, style: const TextStyle(fontSize: 12, color: textTertiary)),
      ],
    ),
  );
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
