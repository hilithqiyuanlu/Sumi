import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LocalSpeechModelFile {
  const LocalSpeechModelFile({
    required this.path,
    required this.sizeBytes,
    required this.sha256,
  });

  final String path;
  final int sizeBytes;
  final String sha256;

  factory LocalSpeechModelFile.fromJson(Map<String, Object?> json) =>
      LocalSpeechModelFile(
        path: json['path'] as String? ?? '',
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        sha256: json['sha256'] as String? ?? '',
      );

  Map<String, Object?> toJson() => {
    'path': path,
    'sizeBytes': sizeBytes,
    'sha256': sha256,
  };
}

/// The fixed, verified SenseVoice package Sumi accepts from ModelScope.
class LocalSpeechModelManifest {
  const LocalSpeechModelManifest({
    required this.id,
    required this.version,
    required this.files,
  });

  final String id;
  final String version;
  final List<LocalSpeechModelFile> files;

  int get totalBytes => files.fold(0, (sum, file) => sum + file.sizeBytes);

  LocalSpeechModelFile fileNamed(String path) => files.firstWhere(
    (file) => file.path == path,
    orElse: () => throw const FormatException('语音模型清单缺少必要文件'),
  );

  factory LocalSpeechModelManifest.fromJson(Map<String, Object?> json) {
    final manifest = LocalSpeechModelManifest(
      id: json['id'] as String? ?? '',
      version: json['version'] as String? ?? '',
      files: (json['files'] as List<Object?>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map(LocalSpeechModelFile.fromJson)
          .toList(growable: false),
    );
    manifest.validate();
    return manifest;
  }

  void validate() {
    if (id != LocalSpeechModelPackage.repositoryId ||
        version.isEmpty ||
        files.isEmpty) {
      throw const FormatException('本地语音模型清单无效');
    }
    for (final file in files) {
      if (file.path.isEmpty ||
          file.path.contains('..') ||
          file.sizeBytes <= 0 ||
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(file.sha256)) {
        throw const FormatException('本地语音模型文件清单无效');
      }
    }
    fileNamed('model.int8.onnx');
    fileNamed('tokens.txt');
    final paths = files.map((file) => file.path).toSet();
    if (files.length != 2 ||
        paths.length != 2 ||
        !paths.containsAll(const {'model.int8.onnx', 'tokens.txt'})) {
      throw const FormatException('本地语音模型包含未声明的运行文件');
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'runtime': 'sherpa-onnx-sensevoice',
    'files': files.map((file) => file.toJson()).toList(growable: false),
  };
}

class LocalSpeechModelPackageException implements Exception {
  const LocalSpeechModelPackageException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Downloads a package into staging first. An incomplete or invalid package is
/// never made active, so an app update or failed download keeps the old model.
class LocalSpeechModelPackage {
  static const repositoryId = 'Hilith/sumi-sensevoice-small-onnx-int8';
  static const _revision = 'master';
  final http.Client _client;
  final Future<Directory> Function() _root;

  LocalSpeechModelPackage({
    http.Client? client,
    Future<Directory> Function()? root,
  }) : _client = client ?? http.Client(),
       _root = root ?? _defaultRoot;

  static Future<Directory> _defaultRoot() async => Directory(
    p.join(
      (await getApplicationSupportDirectory()).path,
      'sumi',
      'models',
      repositoryId,
    ),
  );

  Uri _url(String path) => Uri.parse(
    'https://modelscope.ai/models/$repositoryId/resolve/$_revision/$path',
  );

  Future<LocalSpeechModelManifest> fetchManifest() async {
    final response = await _client
        .get(_url('manifest.json'))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw LocalSpeechModelPackageException(
        '语音模型暂未发布或无法访问（HTTP ${response.statusCode}）',
      );
    }
    try {
      return LocalSpeechModelManifest.fromJson(
        (jsonDecode(response.body) as Map).cast<String, Object?>(),
      );
    } catch (error) {
      if (error is LocalSpeechModelPackageException ||
          error is FormatException) {
        rethrow;
      }
      throw const LocalSpeechModelPackageException('语音模型清单解析失败');
    }
  }

  Future<LocalSpeechModelManifest?> installedManifest() async {
    final directory = await _active();
    final manifestFile = File(p.join(directory.path, 'manifest.json'));
    if (!await manifestFile.exists()) return null;
    try {
      final manifest = LocalSpeechModelManifest.fromJson(
        (jsonDecode(await manifestFile.readAsString()) as Map)
            .cast<String, Object?>(),
      );
      await verify(manifest, directory);
      return manifest;
    } catch (_) {
      return null;
    }
  }

  Future<Directory> download(
    LocalSpeechModelManifest manifest, {
    required void Function(int received, int total) onProgress,
  }) async {
    final directory = Directory(
      p.join((await _root()).path, '.staging-${manifest.version}'),
    );
    await directory.create(recursive: true);
    var completed = 0;
    for (final file in manifest.files) {
      await _downloadFile(
        directory,
        file,
        completed: completed,
        total: manifest.totalBytes,
        onProgress: onProgress,
      );
      completed += file.sizeBytes;
    }
    await verify(manifest, directory);
    await File(
      p.join(directory.path, 'manifest.json'),
    ).writeAsString(jsonEncode(manifest.toJson()));
    return directory;
  }

  Future<void> activate(Directory candidate) async {
    final active = await _active();
    final previous = Directory('${active.path}.previous');
    if (await previous.exists()) await previous.delete(recursive: true);
    if (await active.exists()) await active.rename(previous.path);
    try {
      await candidate.rename(active.path);
      if (await previous.exists()) await previous.delete(recursive: true);
    } catch (_) {
      if (!await active.exists() && await previous.exists()) {
        await previous.rename(active.path);
      }
      rethrow;
    }
  }

  Future<String> modelPath() async =>
      p.join((await _active()).path, 'model.int8.onnx');
  Future<String> tokensPath() async =>
      p.join((await _active()).path, 'tokens.txt');

  Future<void> delete() async {
    final active = await _active();
    if (await active.exists()) await active.delete(recursive: true);
  }

  Future<void> verify(
    LocalSpeechModelManifest manifest,
    Directory directory,
  ) async {
    for (final file in manifest.files) {
      final target = File(p.join(directory.path, file.path));
      if (!await target.exists() || await target.length() != file.sizeBytes) {
        throw const LocalSpeechModelPackageException('语音模型文件不完整');
      }
      final digest = await sha256.bind(target.openRead()).first;
      if (digest.toString().toLowerCase() != file.sha256.toLowerCase()) {
        throw const LocalSpeechModelPackageException('语音模型校验失败');
      }
    }
  }

  Future<void> _downloadFile(
    Directory directory,
    LocalSpeechModelFile file, {
    required int completed,
    required int total,
    required void Function(int received, int total) onProgress,
  }) async {
    final target = File(p.join(directory.path, file.path));
    var retriedFromStart = false;
    await target.parent.create(recursive: true);
    while (true) {
      var existing = await target.exists() ? await target.length() : 0;
      if (existing > file.sizeBytes) {
        await target.delete();
        existing = 0;
      }
      if (existing == file.sizeBytes) {
        try {
          await _verifyFile(target, file);
          onProgress(completed + existing, total);
          return;
        } on LocalSpeechModelPackageException {
          await target.delete();
          existing = 0;
        }
      }
      final request = http.Request('GET', _url(file.path));
      if (existing > 0) request.headers['Range'] = 'bytes=$existing-';
      final response = await _client
          .send(request)
          .timeout(const Duration(minutes: 15));
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw LocalSpeechModelPackageException(
          '语音模型下载失败（HTTP ${response.statusCode}）',
        );
      }
      if (existing > 0 &&
          response.statusCode == 206 &&
          !_startsAt(response.headers['content-range'], existing)) {
        await target.delete();
        if (retriedFromStart) {
          throw const LocalSpeechModelPackageException('语音模型断点下载数据异常');
        }
        retriedFromStart = true;
        continue;
      }
      if (existing > 0 && response.statusCode == 200) {
        await target.delete();
        existing = 0;
      }
      final sink = target.openWrite(
        mode: existing > 0 ? FileMode.append : FileMode.write,
      );
      var received = existing;
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress(completed + received, total);
        }
      } finally {
        await sink.close();
      }
      try {
        await _verifyFile(target, file);
        return;
      } on LocalSpeechModelPackageException {
        if (retriedFromStart) rethrow;
        await target.delete();
        retriedFromStart = true;
      }
    }
  }

  Future<Directory> _active() async =>
      Directory(p.join((await _root()).path, 'active'));

  Future<void> _verifyFile(File target, LocalSpeechModelFile file) async {
    if (!await target.exists() || await target.length() != file.sizeBytes) {
      throw const LocalSpeechModelPackageException('语音模型文件不完整');
    }
    final digest = await sha256.bind(target.openRead()).first;
    if (digest.toString().toLowerCase() != file.sha256.toLowerCase()) {
      throw const LocalSpeechModelPackageException('语音模型校验失败');
    }
  }

  bool _startsAt(String? contentRange, int offset) =>
      RegExp('^bytes $offset-').hasMatch(contentRange ?? '');
}
