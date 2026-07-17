import 'package:flutter/material.dart';

import '../../services/memory_service.dart';
import '../../store/sumi_store.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';

class MemoryCenterPage extends StatefulWidget {
  const MemoryCenterPage({super.key});

  @override
  State<MemoryCenterPage> createState() => _MemoryCenterPageState();
}

class _MemoryCenterPageState extends State<MemoryCenterPage> {
  List<MemoryItem> _items = const [];
  bool _loading = true;
  late final SumiStore _store;

  @override
  void initState() {
    super.initState();
    _store = SumiScope.read(context);
    _store.settingsController.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _store.settingsController.removeListener(_load);
    super.dispose();
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

  Future<void> _showEditor(MemoryItem item) async {
    final saved =
        await showModalBottomSheet<({MemoryType type, String content})>(
          context: context,
          isScrollControlled: true,
          builder: (context) => MemoryEditorSheet(
            initialType: item.type,
            initialContent: item.content,
            onSave: (type, content) =>
                Navigator.pop(context, (type: type, content: content)),
          ),
        );
    if (saved == null || !mounted) return;
    final service = SumiScope.read(context).memoryService;
    if (service != null && saved.content.trim().isNotEmpty) {
      await service.update(
        item.id,
        type: saved.type,
        category: item.category,
        content: saved.content,
      );
      await service.exportUserModel();
      if (mounted) SumiScope.read(context).scheduleLocalIndex();
    }
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
      builder: (context) => Container(
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
          padding: EdgeInsets.fromLTRB(
            s20,
            s10,
            s20,
            MediaQuery.paddingOf(context).bottom + s20,
          ),
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
                  '这条记忆暂无可展示的来源记录。',
                  style: TextStyle(fontSize: 13, color: textSecondary),
                )
              else
                ...evidence.map(_buildEvidence),
            ],
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
    MemoryType.milestone => '里程碑',
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
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : groups.isEmpty
          ? const Center(
              child: Text('暂时没有记忆', style: TextStyle(color: textSecondary)),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(s16, s8, s16, s32),
              children: [
                for (final type in const [
                  MemoryType.explicit,
                  MemoryType.current,
                  MemoryType.milestone,
                ])
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
          _sourceText(item.source),
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
            final store = SumiScope.read(context);
            final service = store.memoryService;
            if (action == 'edit') {
              await _showEditor(item);
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
              if (item.type == MemoryType.milestone) {
                await store.deleteMilestoneMemory(item.id);
              } else {
                await store.deleteMemory(item.id);
              }
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
            if (item.type != MemoryType.milestone)
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
    MemorySource.manual => '历史记录',
    MemorySource.recommendation => '来自建议反馈',
    MemorySource.project => '来自项目',
    MemorySource.legacy => '历史导入',
  };
}

typedef MemoryEditorSave = void Function(MemoryType type, String content);

class MemoryEditorSheet extends StatefulWidget {
  const MemoryEditorSheet({
    required this.initialType,
    required this.initialContent,
    required this.onSave,
    super.key,
  });

  final MemoryType initialType;
  final String initialContent;
  final MemoryEditorSave onSave;

  @override
  State<MemoryEditorSheet> createState() => _MemoryEditorSheetState();
}

class _MemoryEditorSheetState extends State<MemoryEditorSheet> {
  late final TextEditingController _content;
  late final FocusNode _contentFocus;
  late MemoryType _type;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType == MemoryType.current
        ? MemoryType.current
        : MemoryType.explicit;
    _content = TextEditingController(text: widget.initialContent)
      ..selection = TextSelection.collapsed(
        offset: widget.initialContent.length,
      );
    _contentFocus = FocusNode();
  }

  @override
  void dispose() {
    _content.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      s16,
      s16,
      s16,
      MediaQuery.viewInsetsOf(context).bottom + s16,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '编辑记忆',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: s16),
        SegmentedButton<MemoryType>(
          segments: const [
            ButtonSegment(value: MemoryType.explicit, label: Text('明确记忆')),
            ButtonSegment(value: MemoryType.current, label: Text('正在关注')),
          ],
          selected: {_type},
          onSelectionChanged: (next) => setState(() => _type = next.first),
        ),
        const SizedBox(height: s12),
        TextField(
          controller: _content,
          focusNode: _contentFocus,
          autofocus: true,
          decoration: const InputDecoration(labelText: '内容'),
          maxLength: 300,
          maxLines: 3,
        ),
        const SizedBox(height: s8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => widget.onSave(_type, _content.text),
            child: const Text('保存'),
          ),
        ),
      ],
    ),
  );
}
