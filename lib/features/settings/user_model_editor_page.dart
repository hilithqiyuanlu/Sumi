import 'package:flutter/material.dart';

import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';

/// USER_MODEL.md 编辑器页面。
class UserModelEditorPage extends StatefulWidget {
  const UserModelEditorPage({super.key});

  @override
  State<UserModelEditorPage> createState() => _UserModelEditorPageState();
}

class _UserModelEditorPageState extends State<UserModelEditorPage> {
  final _controller = TextEditingController();
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = SumiScope.read(context);
    final ums = store.userModelService;
    if (ums == null) return;
    final content = await ums.readUserModel();
    if (mounted) setState(() { _controller.text = content; _loaded = true; });
  }

  Future<void> _save() async {
    H.click();
    setState(() => _saving = true);
    final store = SumiScope.read(context);
    final ums = store.userModelService;
    if (ums != null) {
      await ums.writeUserModel(_controller.text);
    }
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('记忆已保存'), duration: Duration(seconds: 1), behavior: SnackBarBehavior.floating),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(radiusCard))),
        title: const Text('清空记忆', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: const Text('确定要清空 Sumi 的全部记忆吗？此操作不可撤销。', style: TextStyle(fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('清空', style: TextStyle(color: danger))),
        ],
      ),
    );
    if (confirmed == true) {
      H.medium();
      _controller.clear();
      final store = SumiScope.read(context);
      await store.userModelService?.writeUserModel('');
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: paper,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(s4, s8, s16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text('记忆编辑器', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ink)),
                  const Spacer(),
                ],
              ),
            ),
            // Warning
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: s16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(s12),
                decoration: BoxDecoration(
                  color: warning500.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(radiusPanel),
                ),
                child: const Text(
                  '系统管理区（<!-- SYSTEM-MANAGED --> 之间）会自动覆盖，请勿手动编辑',
                  style: TextStyle(fontSize: 12, color: warning600),
                ),
              ),
            ),
            const SizedBox(height: s12),
            // Editor
            Expanded(
              child: _loaded
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: s16),
                      child: TextField(
                        controller: _controller,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        style: const TextStyle(fontSize: 13, fontFamily: 'monospace', height: 1.5),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.all(s12),
                        ),
                      ),
                    )
                  : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(s16, s8, s16, s16),
              child: Row(
                children: [
                  _TextButton(label: '清空记忆', color: danger, onTap: _clear),
                  const Spacer(),
                  _TextButton(label: '取消', color: ink, onTap: () => Navigator.pop(context)),
                  const SizedBox(width: s8),
                  _FilledButton(label: '保存', loading: _saving, onTap: _save),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilledButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;
  const _FilledButton({required this.label, this.loading = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: s16, vertical: s10),
        decoration: BoxDecoration(color: primary500, borderRadius: BorderRadius.circular(radiusPill)),
        child: loading
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
      ),
    );
  }
}

class _TextButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _TextButton({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
