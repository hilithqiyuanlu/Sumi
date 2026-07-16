import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sumi/services/app_update_service.dart';

class _VersionReader implements AppVersionReader {
  final AppVersion value;
  const _VersionReader(this.value);
  @override
  Future<AppVersion> read() async => value;
}

class _Installer implements AppUpdateInstaller {
  final AppUpdateInstallResult result;
  String? path;
  _Installer(this.result);
  @override
  Future<AppUpdateInstallResult> install(String apkPath) async {
    path = apkPath;
    return result;
  }
}

Map<String, Object?> _manifest(List<int> apk, {int build = 2}) => {
  'version': '1.0.$build',
  'buildNumber': build,
  'notes': '修复测试问题。',
  'apk': {
    'url':
        'https://github.com/hilithqiyuanlu/Sumi/releases/download/v1.0.$build/app.apk',
    'sizeBytes': apk.length,
    'sha256': sha256.convert(apk).toString(),
  },
};

http.Response _json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('发现较高构建号的 HTTPS 更新', () async {
    final apk = utf8.encode('apk-data');
    expect(AppUpdateManifest.fromJson(_manifest(apk)).buildNumber, 2);
    final service = AppUpdateService(
      platform: AppUpdatePlatform.android,
      versions: const _VersionReader(
        AppVersion(version: '1.0.0', buildNumber: 1),
      ),
      client: MockClient((request) async => _json(_manifest(apk))),
    );
    addTearDown(service.close);

    await service.check();

    expect(
      service.state.value.status,
      AppUpdateStatus.available,
      reason: service.state.value.error,
    );
    expect(service.state.value.manifest?.buildNumber, 2);
  });

  test('相同构建号不会提示更新，非法清单会失败', () async {
    final apk = utf8.encode('apk-data');
    final latest = AppUpdateService(
      platform: AppUpdatePlatform.android,
      versions: const _VersionReader(
        AppVersion(version: '1.0.1', buildNumber: 2),
      ),
      client: MockClient((request) async => _json(_manifest(apk))),
    );
    addTearDown(latest.close);
    await latest.check();
    expect(latest.state.value.status, AppUpdateStatus.latest);

    final malformed = AppUpdateService(
      platform: AppUpdatePlatform.android,
      versions: const _VersionReader(
        AppVersion(version: '1.0.0', buildNumber: 1),
      ),
      client: MockClient((request) async => _json({'version': '2'})),
    );
    addTearDown(malformed.close);
    await malformed.check();
    expect(malformed.state.value.status, AppUpdateStatus.failed);
  });

  test('下载校验成功后可请求 Android 系统安装器', () async {
    final root = await Directory.systemTemp.createTemp('sumi-update-test-');
    addTearDown(() => root.delete(recursive: true));
    final apk = utf8.encode('signed-apk-data');
    final installer = _Installer(AppUpdateInstallResult.installerOpened);
    final service = AppUpdateService(
      platform: AppUpdatePlatform.android,
      versions: const _VersionReader(
        AppVersion(version: '1.0.0', buildNumber: 1),
      ),
      installer: installer,
      downloadDirectory: () async => root,
      client: MockClient((request) async {
        if (request.url.path.endsWith('update.json')) {
          return _json(_manifest(apk));
        }
        return http.Response.bytes(apk, 200);
      }),
    );
    addTearDown(service.close);

    await service.check();
    await service.download();
    expect(service.state.value.status, AppUpdateStatus.downloaded);
    expect(await File(p.join(root.path, 'sumi-2.apk')).exists(), isTrue);

    await service.install();
    expect(service.state.value.status, AppUpdateStatus.installing);
    expect(installer.path, isNotNull);
  });

  test('错误哈希不会保留 APK', () async {
    final root = await Directory.systemTemp.createTemp('sumi-update-bad-');
    addTearDown(() => root.delete(recursive: true));
    final manifest = _manifest(utf8.encode('expected'));
    final installer = _Installer(AppUpdateInstallResult.installerOpened);
    final service = AppUpdateService(
      platform: AppUpdatePlatform.android,
      versions: const _VersionReader(
        AppVersion(version: '1.0.0', buildNumber: 1),
      ),
      installer: installer,
      downloadDirectory: () async => root,
      client: MockClient((request) async {
        if (request.url.path.endsWith('update.json')) {
          return _json(manifest);
        }
        return http.Response.bytes(utf8.encode('corrupted'), 200);
      }),
    );
    addTearDown(service.close);

    await service.check();
    await service.download();

    expect(service.state.value.status, AppUpdateStatus.failed);
    expect(installer.path, isNull);
    expect(await File(p.join(root.path, 'sumi-2.apk')).exists(), isFalse);
  });

  test('iOS 从不调用 Android 安装器', () async {
    final apk = utf8.encode('apk-data');
    final installer = _Installer(AppUpdateInstallResult.installerOpened);
    final service = AppUpdateService(
      platform: AppUpdatePlatform.ios,
      versions: const _VersionReader(
        AppVersion(version: '1.0.0', buildNumber: 1),
      ),
      installer: installer,
      client: MockClient((request) async => _json(_manifest(apk))),
    );
    addTearDown(service.close);

    await service.check();
    await service.download();
    await service.install();

    expect(service.state.value.status, AppUpdateStatus.available);
    expect(installer.path, isNull);
  });

  test('安装未知来源权限不足时进入等待状态', () async {
    final root = await Directory.systemTemp.createTemp(
      'sumi-update-permission-',
    );
    addTearDown(() => root.delete(recursive: true));
    final apk = utf8.encode('signed-apk-data');
    final service = AppUpdateService(
      platform: AppUpdatePlatform.android,
      versions: const _VersionReader(
        AppVersion(version: '1.0.0', buildNumber: 1),
      ),
      installer: _Installer(AppUpdateInstallResult.permissionRequired),
      downloadDirectory: () async => root,
      client: MockClient((request) async {
        if (request.url.path.endsWith('update.json')) {
          return _json(_manifest(apk));
        }
        return http.Response.bytes(apk, 200);
      }),
    );
    addTearDown(service.close);

    await service.check();
    await service.download();
    await service.install();

    expect(service.state.value.status, AppUpdateStatus.permissionRequired);
  });
}
