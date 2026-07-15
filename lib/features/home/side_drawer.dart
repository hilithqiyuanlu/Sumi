import 'package:flutter/material.dart';

import '../../store/sumi_store.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';

class SideDrawer extends StatelessWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final VoidCallback onOpenSettings;

  const SideDrawer({
    super.key,
    required this.isOpen,
    required this.onClose,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final drawerWidth = screenWidth * 5 / 6;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      left: isOpen ? 0 : -drawerWidth,
      top: 0,
      bottom: 0,
      width: drawerWidth,
      child: Stack(
        children: [
          Material(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(radius20),
              bottomRight: Radius.circular(radius20),
            ),
            child: Column(
              children: [
                _buildUserProfile(context),
                const Divider(height: 1),
                const Spacer(),
                _buildSettingsButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserProfile(BuildContext context) {
    final store = SumiScope.watchSettings(context);
    final userName = store.appSettings.userName;

    return Padding(
      padding: EdgeInsets.only(
        left: s16,
        right: s16,
        top: s16 + MediaQuery.of(context).padding.top,
        bottom: s16,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: primary100,
              borderRadius: BorderRadius.circular(radiusPill),
            ),
            child: const Icon(
              Icons.person,
              size: 24,
              color: primary500,
            ),
          ),
          const SizedBox(width: s12),
          Expanded(
            child: InkWell(
              onTap: () => _editUserName(context, store),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userName.isEmpty ? '点击设置昵称' : userName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: s12, vertical: s8),
        child: InkWell(
          onTap: () {
            H.click();
            onClose();
            onOpenSettings();
          },
          borderRadius: BorderRadius.circular(radius12),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: s12, vertical: s12),
            child: Row(
              children: [
                Icon(Icons.tune, size: 24, color: textTertiary),
                SizedBox(width: s12),
                Text(
                  '设置',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _editUserName(BuildContext context, SumiStore store) {
    final controller = TextEditingController(text: store.appSettings.userName);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(radiusCard)),
          ),
          title: const Text('设置昵称',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '输入你的昵称'),
            maxLength: 6,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                store.updateUserName(controller.text.trim());
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    ).then((_) => controller.dispose());
  }
}
