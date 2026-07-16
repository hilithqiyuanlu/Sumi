import 'package:flutter/material.dart';

import '../../services/memory_service.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';

class MemoryExtractionDiagnosticsPage extends StatefulWidget {
  const MemoryExtractionDiagnosticsPage({super.key});

  @override
  State<MemoryExtractionDiagnosticsPage> createState() =>
      _MemoryExtractionDiagnosticsPageState();
}

class _MemoryExtractionDiagnosticsPageState
    extends State<MemoryExtractionDiagnosticsPage> {
  late Future<MemoryExtractionDiagnostics> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final service = SumiScope.read(context).memoryService;
    _future =
        service?.extractionDiagnostics() ??
        Future.value(
          const MemoryExtractionDiagnostics(
            applied: 0,
            ignored: 0,
            failed: 0,
            failuresByCategory: {},
          ),
        );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: paper,
    appBar: AppBar(
      title: const Text('记忆采集诊断'),
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: () => setState(_reload),
          icon: const Icon(Icons.refresh, size: iconMedium),
        ),
      ],
    ),
    body: FutureBuilder<MemoryExtractionDiagnostics>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        final failures = data.failuresByCategory.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        return ListView(
          padding: const EdgeInsets.fromLTRB(s16, s16, s16, s24),
          children: [
            const Text(
              '近 7 天，仅显示汇总，不包含用户内容。',
              style: TextStyle(fontSize: 13, color: textSecondary),
            ),
            const SizedBox(height: s12),
            _Summary(data: data),
            if (data.sources.isNotEmpty) ...[
              const SizedBox(height: s24),
              const Text(
                '采集入口',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: s8),
              for (final entry in data.sources.entries)
                _FailureRow(label: _sourceLabel(entry.key), count: entry.value),
            ],
            if (failures.isNotEmpty) ...[
              const SizedBox(height: s24),
              const Text(
                '失败类别',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: s8),
              ...failures.map(
                (entry) => _FailureRow(
                  label: _failureLabel(entry.key),
                  count: entry.value,
                ),
              ),
            ],
          ],
        );
      },
    ),
  );

  static String _failureLabel(String value) => switch (value) {
    'no_valid_decision' => '模型未返回可用结果',
    'validation' => '原话或字段校验失败',
    'replacement' => '替换目标无效',
    'storage' => '本地写入失败',
    'runtime' => '后台运行异常',
    _ => '未知失败',
  };

  static String _sourceLabel(String value) => switch (value) {
    'unified_input' => '统一输入',
    'chat' => '普通聊天',
    _ => '其他入口',
  };
}

class _Summary extends StatelessWidget {
  final MemoryExtractionDiagnostics data;
  const _Summary({required this.data});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(s16),
    decoration: BoxDecoration(
      color: primary50,
      borderRadius: BorderRadius.circular(radius8),
      border: Border.all(color: primary100),
    ),
    child: Row(
      children: [
        _Stat(label: '已保存', value: data.applied),
        _Stat(label: '已忽略', value: data.ignored),
        _Stat(label: '失败', value: data.failed),
        _Stat(label: '重试', value: data.retries),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        const SizedBox(height: s2),
        Text(label, style: const TextStyle(fontSize: 12, color: textSecondary)),
      ],
    ),
  );
}

class _FailureRow extends StatelessWidget {
  final String label;
  final int count;
  const _FailureRow({required this.label, required this.count});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: s8),
    padding: const EdgeInsets.symmetric(horizontal: s14, vertical: s12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius8),
      border: Border.all(color: surfaceChip),
    ),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
        Text(
          '$count 次',
          style: const TextStyle(fontSize: 13, color: textSecondary),
        ),
      ],
    ),
  );
}
