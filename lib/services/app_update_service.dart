import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum AppUpdatePlatform { android, ios, unsupported }

enum AppUpdateStatus {
  idle,
  checking,
  latest,
  available,
  downloading,
  downloaded,
  permissionRequired,
  installing,
  failed,
}

class AppVersion {
  final String version;
  final int buildNumber;

  const AppVersion({required this.version, required this.buildNumber});

  String get display => '$version+$buildNumber';
}

class AppUpdateManifest {
  final String version;
  final int buildNumber;
  final String notes;
  final Uri apkUrl;
  final int sizeBytes;
  final String sha256;

  const AppUpdateManifest({
    required this.version,
    required this.buildNumber,
    required this.notes,
    required this.apkUrl,
    required this.sizeBytes,
    required this.sha256,
  });

  factory AppUpdateManifest.fromJson(Map<String, Object?> json) {
    final apk = (json['apk'] as Map?)?.cast<String, Object?>();
    final url = Uri.tryParse(apk?['url'] as String? ?? '');
    final manifest = AppUpdateManifest(
      version: json['version'] as String? ?? '',
      buildNumber: (json['buildNumber'] as num?)?.toInt() ?? 0,
      notes: json['notes'] as String? ?? '',
      apkUrl: url ?? Uri(),
      sizeBytes: (apk?['sizeBytes'] as num?)?.toInt() ?? 0,
      sha256: apk?['sha256'] as String? ?? '',
    );
    if (manifest.version.isEmpty ||
        manifest.buildNumber <= 0 ||
        manifest.notes.length > 2000 ||
        manifest.apkUrl.scheme != 'https' ||
        manifest.apkUrl.host.isEmpty ||
        manifest.sizeBytes <= 0 ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(manifest.sha256)) {
      throw const AppUpdateException('更新信息格式无效');
    }
    return manifest;
  }
}

class AppUpdateState {
  final AppUpdateStatus status;
  final AppVersion? currentVersion;
  final AppUpdateManifest? manifest;
  final int receivedBytes;
  final int totalBytes;
  final String? error;

  const AppUpdateState({
    this.status = AppUpdateStatus.idle,
    this.currentVersion,
    this.manifest,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.error,
  });

  AppUpdateState copyWith({
    AppUpdateStatus? status,
    AppVersion? currentVersion,
    AppUpdateManifest? manifest,
    int? receivedBytes,
    int? totalBytes,
    String? error,
    bool clearError = false,
  }) => AppUpdateState(
    status: status ?? this.status,
    currentVersion: currentVersion ?? this.currentVersion,
    manifest: manifest ?? this.manifest,
    receivedBytes: receivedBytes ?? this.receivedBytes,
    totalBytes: totalBytes ?? this.totalBytes,
    error: clearError ? null : error ?? this.error,
  );
}

abstract interface class AppVersionReader {
  Future<AppVersion> read();
}

class PackageInfoVersionReader implements AppVersionReader {
  @override
  Future<AppVersion> read() async {
    final info = await PackageInfo.fromPlatform();
    return AppVersion(
      version: info.version,
      buildNumber: int.tryParse(info.buildNumber) ?? 0,
    );
  }
}

enum AppUpdateInstallResult { installerOpened, permissionRequired }

abstract interface class AppUpdateInstaller {
  Future<AppUpdateInstallResult> install(String apkPath);
}

class PlatformAppUpdateInstaller implements AppUpdateInstaller {
  static const _channel = MethodChannel('com.hellosumitech.sumi/app_update');

  @override
  Future<AppUpdateInstallResult> install(String apkPath) async {
    try {
      final result = await _channel.invokeMethod<String>('install', {
        'apkPath': apkPath,
      });
      return switch (result) {
        'installer_opened' => AppUpdateInstallResult.installerOpened,
        'permission_required' => AppUpdateInstallResult.permissionRequired,
        _ => throw const AppUpdateException('无法打开系统安装器'),
      };
    } on PlatformException catch (error) {
      throw AppUpdateException(error.message ?? '无法打开系统安装器');
    }
  }
}

/// Downloads only a signed ARM64 APK. Models live in application support and
/// are never read, moved, or deleted by this service.
class AppUpdateService {
  static final manifestUrl = Uri.parse(
    'https://raw.githubusercontent.com/hilithqiyuanlu/Sumi/main/release/update.json',
  );

  final http.Client _client;
  final AppVersionReader _versions;
  final AppUpdateInstaller _installer;
  final AppUpdatePlatform _platform;
  final Future<Directory> Function() _downloadDirectory;
  final bool _ownsClient;
  final ValueNotifier<AppUpdateState> state = ValueNotifier(
    const AppUpdateState(),
  );

  AppUpdateService({
    http.Client? client,
    AppVersionReader? versions,
    AppUpdateInstaller? installer,
    AppUpdatePlatform? platform,
    Future<Directory> Function()? downloadDirectory,
  }) : _client = client ?? http.Client(),
       _versions = versions ?? PackageInfoVersionReader(),
       _installer = installer ?? PlatformAppUpdateInstaller(),
       _platform = platform ?? _defaultPlatform(),
       _downloadDirectory = downloadDirectory ?? _defaultDownloadDirectory,
       _ownsClient = client == null;

  static AppUpdatePlatform _defaultPlatform() =>
      switch (defaultTargetPlatform) {
        TargetPlatform.android => AppUpdatePlatform.android,
        TargetPlatform.iOS => AppUpdatePlatform.ios,
        _ => AppUpdatePlatform.unsupported,
      };

  static Future<Directory> _defaultDownloadDirectory() async =>
      Directory(p.join((await getTemporaryDirectory()).path, 'sumi-updates'));

  Future<void> prepare() async {
    if (state.value.currentVersion != null) return;
    try {
      final current = await _versions.read();
      _emit(state.value.copyWith(currentVersion: current, clearError: true));
    } catch (_) {
      _emit(
        state.value.copyWith(
          currentVersion: const AppVersion(version: '未知', buildNumber: 0),
        ),
      );
    }
  }

  Future<void> check() async {
    await prepare();
    final current = state.value.currentVersion!;
    _emit(
      AppUpdateState(status: AppUpdateStatus.checking, currentVersion: current),
    );
    try {
      final response = await _client
          .get(manifestUrl)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw AppUpdateException('检查更新失败（HTTP ${response.statusCode}）');
      }
      final payload = (jsonDecode(response.body) as Map)
          .cast<String, Object?>();
      final manifest = AppUpdateManifest.fromJson(payload);
      _emit(
        AppUpdateState(
          status: manifest.buildNumber > current.buildNumber
              ? AppUpdateStatus.available
              : AppUpdateStatus.latest,
          currentVersion: current,
          manifest: manifest,
        ),
      );
    } on TimeoutException {
      _fail(current, '检查更新超时，请稍后重试');
    } on AppUpdateException catch (error) {
      _fail(current, error.message);
    } catch (_) {
      _fail(current, '检查更新失败，请检查网络后重试');
    }
  }

  Future<void> download() async {
    final current = state.value.currentVersion;
    final manifest = state.value.manifest;
    if (current == null || manifest == null) return;
    if (_platform != AppUpdatePlatform.android) return;
    _emit(
      AppUpdateState(
        status: AppUpdateStatus.downloading,
        currentVersion: current,
        manifest: manifest,
        totalBytes: manifest.sizeBytes,
      ),
    );
    Directory? directory;
    File? temporary;
    try {
      directory = await _downloadDirectory();
      final file = File(
        p.join(directory.path, 'sumi-${manifest.buildNumber}.apk'),
      );
      temporary = File('${file.path}.part');
      await directory.create(recursive: true);
      if (await file.exists() && await _matches(file, manifest)) {
        _emit(
          AppUpdateState(
            status: AppUpdateStatus.downloaded,
            currentVersion: current,
            manifest: manifest,
            receivedBytes: manifest.sizeBytes,
            totalBytes: manifest.sizeBytes,
          ),
        );
        return;
      }
      if (await temporary.exists()) await temporary.delete();
      final response = await _client
          .send(http.Request('GET', manifest.apkUrl))
          .timeout(const Duration(minutes: 10));
      if (response.statusCode != 200) {
        throw AppUpdateException('更新包下载失败（HTTP ${response.statusCode}）');
      }
      var received = 0;
      final sink = temporary.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          _emit(
            AppUpdateState(
              status: AppUpdateStatus.downloading,
              currentVersion: current,
              manifest: manifest,
              receivedBytes: received,
              totalBytes: manifest.sizeBytes,
            ),
          );
        }
      } finally {
        await sink.close();
      }
      if (!await _matches(temporary, manifest)) {
        throw const AppUpdateException('更新包校验失败，请重新下载');
      }
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
      _emit(
        AppUpdateState(
          status: AppUpdateStatus.downloaded,
          currentVersion: current,
          manifest: manifest,
          receivedBytes: manifest.sizeBytes,
          totalBytes: manifest.sizeBytes,
        ),
      );
    } on TimeoutException {
      _fail(current, '更新包下载超时，请重新下载', manifest: manifest);
    } on AppUpdateException catch (error) {
      _fail(current, error.message, manifest: manifest);
    } catch (_) {
      _fail(current, '更新包下载失败，请检查网络后重试', manifest: manifest);
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  Future<void> install() async {
    final current = state.value.currentVersion;
    final manifest = state.value.manifest;
    if (current == null ||
        manifest == null ||
        _platform != AppUpdatePlatform.android) {
      return;
    }
    final file = File(
      p.join(
        (await _downloadDirectory()).path,
        'sumi-${manifest.buildNumber}.apk',
      ),
    );
    if (!await _matches(file, manifest)) {
      _fail(current, '更新包不可用，请重新下载', manifest: manifest);
      return;
    }
    _emit(
      AppUpdateState(
        status: AppUpdateStatus.installing,
        currentVersion: current,
        manifest: manifest,
        receivedBytes: manifest.sizeBytes,
        totalBytes: manifest.sizeBytes,
      ),
    );
    try {
      final result = await _installer.install(file.path);
      _emit(
        AppUpdateState(
          status: result == AppUpdateInstallResult.permissionRequired
              ? AppUpdateStatus.permissionRequired
              : AppUpdateStatus.installing,
          currentVersion: current,
          manifest: manifest,
          receivedBytes: manifest.sizeBytes,
          totalBytes: manifest.sizeBytes,
        ),
      );
    } on AppUpdateException catch (error) {
      _fail(current, error.message, manifest: manifest);
    } catch (_) {
      _fail(current, '无法打开系统安装器', manifest: manifest);
    }
  }

  Future<bool> _matches(File file, AppUpdateManifest manifest) async {
    if (!await file.exists() || await file.length() != manifest.sizeBytes) {
      return false;
    }
    final actual = (await sha256.bind(file.openRead()).first).toString();
    return actual.toLowerCase() == manifest.sha256.toLowerCase();
  }

  void _fail(
    AppVersion current,
    String message, {
    AppUpdateManifest? manifest,
  }) => _emit(
    AppUpdateState(
      status: AppUpdateStatus.failed,
      currentVersion: current,
      manifest: manifest,
      error: message,
    ),
  );

  void _emit(AppUpdateState value) => state.value = value;

  void close() {
    if (_ownsClient) _client.close();
    state.dispose();
  }
}

class AppUpdateException implements Exception {
  final String message;
  const AppUpdateException(this.message);
  @override
  String toString() => message;
}
