import 'package:flutter/material.dart';

import '../../services/user_model_service.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';

class UserModelPage extends StatefulWidget {
  const UserModelPage({super.key});

  @override
  State<UserModelPage> createState() => _UserModelPageState();
}

class _UserModelPageState extends State<UserModelPage> {
  late Future<List<UserModelItem>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final store = SumiScope.read(context);
    _future = store.userModels
        .syncFromImplicit(store.memoryService!)
        .then((_) => store.userModels.list());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: paper,
    appBar: AppBar(title: const Text('用户模型')),
    body: FutureBuilder<List<UserModelItem>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!;
        if (items.isEmpty) {
          return const Center(
            child: Text('暂时没有可用的行为观察', style: TextStyle(color: textSecondary)),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(s16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: s8),
          itemBuilder: (context, index) => _item(items[index]),
        );
      },
    ),
  );

  Widget _item(UserModelItem item) {
    final store = SumiScope.read(context);
    final status = switch (item.status) {
      UserModelStatus.active => '建议排序参考',
      UserModelStatus.observing => '观察中',
      UserModelStatus.disabled => '已关闭',
    };
    return GestureDetector(
      onTap: () => _showEvidence(item),
      child: Container(
        padding: const EdgeInsets.fromLTRB(s16, s14, s8, s14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius8),
          border: Border.all(color: line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.content,
                    style: const TextStyle(fontSize: 15, color: ink),
                  ),
                  const SizedBox(height: s6),
                  Text(
                    '$status · 可信度 ${(item.confidence * 100).round()}%',
                    style: const TextStyle(fontSize: 12, color: textSecondary),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: '更多操作',
              onSelected: (action) async {
                if (action == 'disable') {
                  await store.setUserModelStatus(
                    item.id,
                    UserModelStatus.disabled,
                  );
                } else if (action == 'enable') {
                  await store.setUserModelStatus(
                    item.id,
                    item.confidence >= .85
                        ? UserModelStatus.active
                        : UserModelStatus.observing,
                  );
                } else {
                  await store.deleteUserModel(item.id);
                }
                if (mounted) setState(_reload);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: item.status == UserModelStatus.disabled
                      ? 'enable'
                      : 'disable',
                  child: Text(
                    item.status == UserModelStatus.disabled ? '重新启用' : '关闭',
                  ),
                ),
                const PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEvidence(UserModelItem item) async {
    final evidence = await SumiScope.read(
      context,
    ).userModels.evidenceFor(item.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => ListView(
        padding: const EdgeInsets.all(s20),
        children: [
          const Text(
            '来源记录',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: s12),
          for (final entry in evidence)
            Padding(
              padding: const EdgeInsets.only(bottom: s10),
              child: Text(
                entry.summary,
                style: const TextStyle(fontSize: 14, color: ink),
              ),
            ),
          if (evidence.isEmpty)
            const Text('暂无可展示的来源记录', style: TextStyle(color: textSecondary)),
        ],
      ),
    );
  }
}
