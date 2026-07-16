import 'package:flutter/material.dart';

import '../../services/memory_service.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';

class MemoryCenterPage extends StatefulWidget {
  const MemoryCenterPage({super.key});

  @override
  State<MemoryCenterPage> createState() => _MemoryCenterPageState();
}

class _MemoryCenterPageState extends State<MemoryCenterPage> {
  List<MemoryItem> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final service = SumiScope.read(context).memoryService;
    final items = await service?.list() ?? const <MemoryItem>[];
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  Future<void> _showEditor({MemoryItem? item}) async {
    final content = TextEditingController(text: item?.content ?? '');
    final category = TextEditingController(text: item?.category ?? '偏好');
    final contentFocus = FocusNode();
    var type = item?.type == MemoryType.current
        ? MemoryType.current
        : MemoryType.explicit;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            s16,
            s16,
            s16,
            MediaQuery.of(context).viewInsets.bottom + s16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item == null ? '添加记忆' : '编辑记忆',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: s16),
              SegmentedButton<MemoryType>(
                segments: const [
                  ButtonSegment(
                    value: MemoryType.explicit,
                    label: Text('明确记忆'),
                  ),
                  ButtonSegment(value: MemoryType.current, label: Text('正在关注')),
                ],
                selected: {type},
                onSelectionChanged: (next) =>
                    setModalState(() => type = next.first),
              ),
              const SizedBox(height: s12),
              TextField(
                controller: content,
                focusNode: contentFocus,
                autofocus: item == null,
                decoration: const InputDecoration(labelText: '内容'),
                maxLength: 300,
                maxLines: 3,
              ),
              TextField(
                controller: category,
                decoration: const InputDecoration(labelText: '分类'),
                maxLength: 30,
              ),
              const SizedBox(height: s8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true) {
      content.dispose();
      category.dispose();
      contentFocus.dispose();
      return;
    }
    if (!mounted) {
      content.dispose();
      category.dispose();
      contentFocus.dispose();
      return;
    }
    final service = SumiScope.read(context).memoryService;
    if (service != null &&
        content.text.trim().isNotEmpty &&
        category.text.trim().isNotEmpty) {
      if (item == null) {
        await service.addManual(
          type: type,
          category: category.text,
          content: content.text,
        );
      } else {
        await service.update(
          item.id,
          category: category.text,
          content: content.text,
          projectId: item.projectId,
        );
      }
      await service.exportUserModel();
      if (mounted) SumiScope.read(context).scheduleLocalIndex();
    }
    content.dispose();
    category.dispose();
    contentFocus.dispose();
    await _load();
  }

  Future<void> _showDetails(MemoryItem item) async {
    final service = SumiScope.read(context).memoryService;
    final evidence =
        await service?.evidenceFor(item.id) ?? const <MemoryEvidence>[];
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.78,
          ),
          decoration: const BoxDecoration(
            color: paper,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(radiusCardHeader),
            ),
            boxShadow: shadow4,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(s20, s10, s20, s20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: line,
                      borderRadius: BorderRadius.circular(radiusPill),
                    ),
                  ),
                ),
                const SizedBox(height: s16),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '记忆详情',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: iconMedium),
                    ),
                  ],
                ),
                const SizedBox(height: s12),
                Wrap(
                  spacing: s8,
                  runSpacing: s8,
                  children: [
                    _detailTag(_titleFor(item.type), primary50, primary700),
                    _detailTag(item.category, surfaceChip, textSecondary),
                  ],
                ),
                const SizedBox(height: s20),
                Text(
                  item.content,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                    color: ink,
                  ),
                ),
                const SizedBox(height: s20),
                Text(
                  evidence.isEmpty ? '暂无来源记录' : '来源记录',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textTertiary,
                  ),
                ),
                const SizedBox(height: s8),
                if (evidence.isEmpty)
                  const Text(
                    '这条记忆由手动添加或历史数据导入。',
                    style: TextStyle(fontSize: 13, color: textSecondary),
                  )
                else
                  ...evidence.map(_buildEvidence),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailTag(String label, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: s10, vertical: s6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radiusPill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }

  Widget _buildEvidence(MemoryEvidence entry) {
    final occurredAt = entry.occurredAt.toLocal();
    final date =
        '${occurredAt.year}/${occurredAt.month.toString().padLeft(2, '0')}/${occurredAt.day.toString().padLeft(2, '0')} '
        '${occurredAt.hour.toString().padLeft(2, '0')}:${occurredAt.minute.toString().padLeft(2, '0')}';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: s8),
      padding: const EdgeInsets.all(s12),
      decoration: BoxDecoration(
        color: surfaceAlt,
        borderRadius: BorderRadius.circular(radius8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.summary,
            style: const TextStyle(fontSize: 13, color: ink, height: 1.4),
          ),
          const SizedBox(height: s4),
          Text(date, style: const TextStyle(fontSize: 11, color: textTertiary)),
        ],
      ),
    );
  }

  String _titleFor(MemoryType type) => switch (type) {
    MemoryType.current => '正在关注',
    MemoryType.explicit => '你明确告诉我的',
    MemoryType.implicit => '系统从反馈中学到的',
    MemoryType.imported => '已停用 / 历史导入',
  };

  @override
  Widget build(BuildContext context) {
    final groups = <MemoryType, List<MemoryItem>>{};
    for (final item in _items) {
      final group =
          item.status == MemoryStatus.active && item.type != MemoryType.imported
          ? item.type
          : MemoryType.imported;
      groups.putIfAbsent(group, () => []).add(item);
    }
    return Scaffold(
      backgroundColor: paper,
      appBar: AppBar(title: const Text('记忆')),
      floatingActionButton: FloatingActionButton(
        tooltip: '添加记忆',
        backgroundColor: primary500,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
        ),
        onPressed: () {
          H.light();
          _showEditor();
        },
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.fromLTRB(s16, s8, s16, s32),
              children: [
                for (final type in MemoryType.values)
                  if ((groups[type] ?? const []).isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: s16, bottom: s8),
                      child: Text(
                        _titleFor(type),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textSecondary,
                        ),
                      ),
                    ),
                    ...groups[type]!.map(_buildItem),
                  ],
              ],
            ),
    );
  }

  Widget _buildItem(MemoryItem item) => Container(
    margin: const EdgeInsets.only(bottom: s8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radiusCard),
      border: Border.all(color: line),
      boxShadow: const [...shadow1],
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radiusCard),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: s16, right: s8),
        title: Text(
          item.content,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${item.category} · ${_sourceText(item.source)}',
          style: const TextStyle(fontSize: 12, color: textSecondary),
        ),
        onTap: () => _showDetails(item),
        trailing: PopupMenuButton<String>(
          tooltip: '更多操作',
          icon: const Icon(
            Icons.more_horiz,
            size: iconMedium,
            color: textTertiary,
          ),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius8),
          ),
          color: paper,
          elevation: 2,
          onSelected: (action) async {
            final service = SumiScope.read(context).memoryService;
            if (action == 'edit') {
              await _showEditor(item: item);
            }
            if (action == 'end') {
              await service?.setStatus(item.id, MemoryStatus.inactive);
            }
            if (action == 'toggle') {
              await service?.setStatus(
                item.id,
                item.status == MemoryStatus.active
                    ? MemoryStatus.disabled
                    : MemoryStatus.active,
              );
            }
            if (action == 'delete') {
              await service?.delete(item.id);
            }
            await service?.exportUserModel();
            if (mounted) SumiScope.read(context).scheduleLocalIndex();
            await _load();
          },
          itemBuilder: (_) => [
            if (item.type == MemoryType.explicit ||
                item.type == MemoryType.current)
              const PopupMenuItem(value: 'edit', child: Text('编辑')),
            if (item.type == MemoryType.current &&
                item.status == MemoryStatus.active)
              const PopupMenuItem(value: 'end', child: Text('结束当前事项')),
            PopupMenuItem(
              value: 'toggle',
              child: Text(item.status == MemoryStatus.active ? '停用' : '重新启用'),
            ),
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      ),
    ),
  );

  String _sourceText(MemorySource source) => switch (source) {
    MemorySource.userMessage => '来自对话',
    MemorySource.manual => '手动添加',
    MemorySource.recommendation => '来自建议反馈',
    MemorySource.project => '来自项目',
    MemorySource.legacy => '历史导入',
  };
}
