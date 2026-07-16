import 'package:flutter/material.dart';

import '../../services/local_text_generation_coordinator.dart';
import '../../services/local_retrieval_coordinator.dart';
import '../../services/model_package_manager.dart';
import '../../store/sumi_store.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';

class LocalIntelligencePage extends StatelessWidget {
  const LocalIntelligencePage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.watchSettings(context);
    final retrieval = store.localRetrievalState;
    final retrievalProgress = retrieval.totalBytes == 0
        ? 0.0
        : retrieval.downloadedBytes / retrieval.totalBytes;
    final index = retrieval.indexProgress;
    final indexProgress = index.total == 0
        ? 0.0
        : index.completed / index.total;
    final retrievalReady =
        retrieval.packageStatus == LocalModelPackageStatus.ready;
    final retrievalBusy = switch (retrieval.packageStatus) {
      LocalModelPackageStatus.checking ||
      LocalModelPackageStatus.downloading ||
      LocalModelPackageStatus.verifying => true,
      _ => false,
    };
    final text = store.localTextModelState;
    final textBusy = switch (text.status) {
      LocalTextModelStatus.checking ||
      LocalTextModelStatus.downloading ||
      LocalTextModelStatus.loading => true,
      _ => false,
    };
    final textProgress = text.totalBytes == 0
        ? 0.0
        : text.receivedBytes / text.totalBytes;

    return Scaffold(
      backgroundColor: paper,
      appBar: AppBar(title: const Text('本地智能')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(s16, s8, s16, s24),
        children: [
          const _LocalIntro(),
          const SizedBox(height: s24),
          const _SectionLabel('本地生成'),
          const SizedBox(height: s8),
          _TextModelStatusCard(
            state: text,
            busy: textBusy,
            enabled: store.localTextGenerationEnabled,
            onEnabledChanged: (value) {
              H.click();
              store.setLocalTextGenerationEnabled(value);
            },
          ),
          if (textBusy || text.totalBytes > 0) ...[
            const SizedBox(height: s16),
            _ProgressPanel(
              title: _textStatusLabel(text.status),
              value: textProgress == 0 ? null : textProgress,
              detail:
                  '${_bytes(text.receivedBytes)} / ${_bytes(text.totalBytes)}',
            ),
          ],
          if (text.error != null) ...[
            const SizedBox(height: s16),
            _ErrorPanel(text.error!),
          ],
          const SizedBox(height: s16),
          if (text.status != LocalTextModelStatus.ready)
            FilledButton.icon(
              onPressed: textBusy ? null : store.downloadLocalTextModel,
              icon: const Icon(Icons.download_outlined, size: iconSmall),
              label: Text(textBusy ? '正在准备模型' : '下载本地模型'),
            )
          else
            OutlinedButton.icon(
              onPressed: () => _confirmDeleteTextModel(context, store),
              style: OutlinedButton.styleFrom(foregroundColor: danger),
              icon: const Icon(Icons.delete_outline, size: iconSmall),
              label: const Text('删除模型'),
            ),
          const SizedBox(height: s24),
          const _SectionLabel('本地检索'),
          const SizedBox(height: s8),
          _ModelStatusCard(
            state: retrieval,
            ready: retrievalReady,
            busy: retrievalBusy,
          ),
          if (retrievalBusy || retrieval.totalBytes > 0) ...[
            const SizedBox(height: s16),
            _ProgressPanel(
              title: _retrievalStatusLabel(retrieval),
              value: retrievalProgress == 0 ? null : retrievalProgress,
              detail:
                  '${_bytes(retrieval.downloadedBytes)} / ${_bytes(retrieval.totalBytes)}',
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
          if (retrieval.error != null) ...[
            const SizedBox(height: s16),
            _ErrorPanel(retrieval.error!),
          ],
          const SizedBox(height: s16),
          if (!retrievalReady)
            FilledButton.icon(
              onPressed: retrievalBusy
                  ? null
                  : () {
                      H.light();
                      store.downloadLocalRetrievalModel();
                    },
              icon: const Icon(Icons.download_outlined, size: iconSmall),
              label: Text(retrievalBusy ? '正在准备模型' : '下载本地模型'),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: retrievalBusy
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
          if (retrievalBusy || index.running)
            TextButton.icon(
              onPressed: store.cancelLocalRetrievalWork,
              icon: const Icon(Icons.pause_circle_outline, size: iconSmall),
              label: const Text('暂停当前任务'),
            ),
        ],
      ),
    );
  }

  static String _retrievalStatusLabel(LocalRetrievalState state) =>
      switch (state.packageStatus) {
        LocalModelPackageStatus.unavailable => '尚未下载',
        LocalModelPackageStatus.checking => '正在检查模型包',
        LocalModelPackageStatus.downloading => '正在下载',
        LocalModelPackageStatus.verifying => '正在校验',
        LocalModelPackageStatus.ready => '已就绪',
        LocalModelPackageStatus.failed => '不可用',
      };

  static String _textStatusLabel(LocalTextModelStatus status) =>
      switch (status) {
        LocalTextModelStatus.unavailable => '尚未下载',
        LocalTextModelStatus.checking => '正在检查模型包',
        LocalTextModelStatus.downloading => '正在下载',
        LocalTextModelStatus.loading => '正在加载',
        LocalTextModelStatus.ready => '已就绪',
        LocalTextModelStatus.failed => '不可用',
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

  Future<void> _confirmDeleteTextModel(
    BuildContext context,
    AppStore store,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
    );
    if (confirmed == true) await store.deleteLocalTextModel();
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
              '本地智能',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: s4),
            Text(
              '模型、检索和学习记录均在设备上处理。',
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
                LocalIntelligencePage._retrievalStatusLabel(state),
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

class _TextModelStatusCard extends StatelessWidget {
  final LocalTextModelState state;
  final bool busy;
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;

  const _TextModelStatusCard({
    required this.state,
    required this.busy,
    required this.enabled,
    required this.onEnabledChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ready = state.status == LocalTextModelStatus.ready;
    return Container(
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
                  LocalIntelligencePage._textStatusLabel(state.status),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: s12),
          const _Row(label: '模型', value: 'Qwen3.5-0.8B · Q4_K_M'),
          const _Row(label: '用途', value: '短任务生成'),
          if (state.version != null) _Row(label: '版本', value: state.version!),
          const Divider(height: s24),
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '使用本地生成',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: s2),
                    Text(
                      '关闭后短任务均使用 Flash',
                      style: TextStyle(fontSize: 12, color: textTertiary),
                    ),
                  ],
                ),
              ),
              Switch(value: enabled, onChanged: onEnabledChanged),
            ],
          ),
        ],
      ),
    );
  }
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

class _ErrorPanel extends StatelessWidget {
  final String message;
  const _ErrorPanel(this.message);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(s12),
    decoration: BoxDecoration(
      color: error50,
      borderRadius: BorderRadius.circular(radius8),
      border: Border.all(color: error100),
    ),
    child: Text(message, style: const TextStyle(fontSize: 13, color: danger)),
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
