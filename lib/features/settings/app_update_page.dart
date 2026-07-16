import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/app_update_service.dart';
import '../../store/sumi_store.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';

class AppUpdatePage extends StatefulWidget {
  const AppUpdatePage({super.key});

  @override
  State<AppUpdatePage> createState() => _AppUpdatePageState();
}

class _AppUpdatePageState extends State<AppUpdatePage> {
  late final AppStore _store;

  @override
  void initState() {
    super.initState();
    _store = SumiScope.read(context);
    unawaited(_store.prepareAppUpdate());
  }

  @override
  Widget build(BuildContext context) {
    final state = SumiScope.watchSettings(context).appUpdateState;
    final isIos = Theme.of(context).platform == TargetPlatform.iOS;
    final busy =
        state.status == AppUpdateStatus.checking ||
        state.status == AppUpdateStatus.downloading ||
        state.status == AppUpdateStatus.installing;
    final progress = state.totalBytes == 0
        ? 0.0
        : state.receivedBytes / state.totalBytes;
    final manifest = state.manifest;

    return Scaffold(
      backgroundColor: paper,
      appBar: AppBar(title: const Text('应用更新')),
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
            child: Text(
              isIos
                  ? 'iOS 版本会显示与 Android 相同的更新信息。当前需要通过 Xcode 安装新版本。'
                  : '仅下载已校验的 ARM64 更新包。安装仍需在 Android 系统页面确认。',
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: textTertiary,
              ),
            ),
          ),
          const SizedBox(height: s20),
          _Info(label: '当前版本', value: state.currentVersion?.display ?? '正在读取'),
          if (manifest != null) ...[
            _Info(
              label: '最新版本',
              value: '${manifest.version}+${manifest.buildNumber}',
            ),
            _Info(label: '更新大小', value: _bytes(manifest.sizeBytes)),
            const SizedBox(height: s12),
            const Text(
              '更新说明',
              style: TextStyle(fontSize: 13, color: textTertiary),
            ),
            const SizedBox(height: s6),
            Text(
              manifest.notes,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
          ],
          if (state.status == AppUpdateStatus.downloading) ...[
            const SizedBox(height: s20),
            LinearProgressIndicator(value: progress == 0 ? null : progress),
            const SizedBox(height: s6),
            Text(
              '${_bytes(state.receivedBytes)} / ${_bytes(state.totalBytes)}',
              style: const TextStyle(fontSize: 12, color: textTertiary),
            ),
          ],
          if (state.status == AppUpdateStatus.permissionRequired)
            const Padding(
              padding: EdgeInsets.only(top: s16),
              child: Text(
                '请在系统设置中允许 Sumi 安装未知应用，然后返回此页再次点击安装。',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: textTertiary,
                ),
              ),
            ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(top: s16),
              child: Text(state.error!, style: const TextStyle(color: danger)),
            ),
          const SizedBox(height: s24),
          _actions(state, busy, isIos),
        ],
      ),
    );
  }

  Widget _actions(AppUpdateState state, bool busy, bool isIos) {
    if (isIos) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: busy
                ? null
                : () {
                    H.light();
                    unawaited(_store.checkForAppUpdate());
                  },
            icon: const Icon(Icons.system_update_alt_outlined, size: iconSmall),
            label: Text(busy ? '正在检查' : '检查更新'),
          ),
          if (state.status == AppUpdateStatus.available) ...[
            const SizedBox(height: s10),
            OutlinedButton.icon(
              onPressed: null,
              icon: Icon(Icons.desktop_windows_outlined, size: iconSmall),
              label: Text('请通过 Xcode 安装更新'),
            ),
          ],
        ],
      );
    }
    return switch (state.status) {
      AppUpdateStatus.available ||
      AppUpdateStatus.failed ||
      AppUpdateStatus.latest ||
      AppUpdateStatus.idle => FilledButton.icon(
        onPressed: busy
            ? null
            : state.status == AppUpdateStatus.available ||
                  (state.status == AppUpdateStatus.failed &&
                      state.manifest != null)
            ? () {
                H.light();
                unawaited(_store.downloadAppUpdate());
              }
            : () {
                H.light();
                unawaited(_store.checkForAppUpdate());
              },
        icon: Icon(
          state.status == AppUpdateStatus.available ||
                  (state.status == AppUpdateStatus.failed &&
                      state.manifest != null)
              ? Icons.download_outlined
              : Icons.system_update_alt_outlined,
          size: iconSmall,
        ),
        label: Text(
          state.status == AppUpdateStatus.available
              ? '下载更新'
              : state.status == AppUpdateStatus.failed && state.manifest != null
              ? '重新下载'
              : '检查更新',
        ),
      ),
      AppUpdateStatus.downloaded ||
      AppUpdateStatus.permissionRequired => FilledButton.icon(
        onPressed: () {
          H.light();
          unawaited(_store.installAppUpdate());
        },
        icon: const Icon(Icons.install_mobile_outlined, size: iconSmall),
        label: const Text('安装更新'),
      ),
      AppUpdateStatus.checking ||
      AppUpdateStatus.downloading ||
      AppUpdateStatus.installing => FilledButton.icon(
        onPressed: null,
        icon: const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        label: Text(
          state.status == AppUpdateStatus.downloading ? '正在下载' : '正在处理',
        ),
      ),
    };
  }

  static String _bytes(int value) {
    if (value <= 0) return '0 MB';
    return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
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
          width: 72,
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
