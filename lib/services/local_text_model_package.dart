import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LocalTextModelManifest {
  final String id;
  final String version;
  final String modelFile;
  final int sizeBytes;
  final String sha256;

  const LocalTextModelManifest({
    required this.id,
    required this.version,
    required this.modelFile,
    required this.sizeBytes,
    required this.sha256,
  });

  factory LocalTextModelManifest.fromJson(Map<String, Object?> json) {
    final files = (json['files'] as List<Object?>? ?? const [])
        .whereType<Map<String, Object?>>()
        .toList(growable: false);
    final model = files
        .where((file) => file['path'] == 'model.gguf')
        .firstOrNull;
    final manifest = LocalTextModelManifest(
      id: json['id'] as String? ?? '',
      version: json['version'] as String? ?? '',
      modelFile: model?['path'] as String? ?? '',
      sizeBytes: (model?['sizeBytes'] as num?)?.toInt() ?? 0,
      sha256: model?['sha256'] as String? ?? '',
    );
    if (manifest.id != LocalTextModelPackage.repositoryId ||
        manifest.version.isEmpty ||
        manifest.modelFile != 'model.gguf' ||
        manifest.sizeBytes <= 0 ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(manifest.sha256)) {
      throw const FormatException('本地文本模型清单无效');
    }
    return manifest;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'runtime': 'gguf',
    'files': [
      {'path': modelFile, 'sizeBytes': sizeBytes, 'sha256': sha256},
    ],
  };
}

/// Downloads only Sumi's pinned Qwen package and verifies it before activation.
class LocalTextModelPackage {
  static const repositoryId = 'Hilith/qwen3.5-0.8b-gguf-q4km';
  static const _revision = 'master';
  final http.Client _client;
  final Future<Directory> Function() _root;

  LocalTextModelPackage({
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

  Future<LocalTextModelManifest> fetchManifest() async {
    final response = await _client
        .get(_url('manifest.json'))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw LocalTextModelPackageException(
        '文本模型暂未发布或无法访问（HTTP ${response.statusCode}）',
      );
    }
    return LocalTextModelManifest.fromJson(
      (jsonDecode(response.body) as Map).cast<String, Object?>(),
    );
  }

  Future<LocalTextModelManifest?> installedManifest() async {
    final file = File(p.join((await _active()).path, 'manifest.json'));
    if (!await file.exists()) return null;
    try {
      final manifest = LocalTextModelManifest.fromJson(
        (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>(),
      );
      await _verify(manifest, await _active());
      return manifest;
    } catch (_) {
      return null;
    }
  }

  Future<Directory> download(
    LocalTextModelManifest manifest, {
    required void Function(int received, int total) onProgress,
  }) async {
    final directory = Directory(
      p.join((await _root()).path, '.staging-${manifest.version}'),
    );
    await directory.create(recursive: true);
    final target = File(p.join(directory.path, manifest.modelFile));
    var existing = await target.exists() ? await target.length() : 0;
    if (existing > manifest.sizeBytes) {
      await target.delete();
      existing = 0;
    }
    final request = http.Request('GET', _url(manifest.modelFile));
    if (existing > 0) request.headers['Range'] = 'bytes=$existing-';
    final response = await _client
        .send(request)
        .timeout(const Duration(minutes: 15));
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw LocalTextModelPackageException(
        '文本模型下载失败（HTTP ${response.statusCode}）',
      );
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
        onProgress(received, manifest.sizeBytes);
      }
    } finally {
      await sink.close();
    }
    await _verify(manifest, directory);
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
      p.join((await _active()).path, 'model.gguf');

  Future<void> delete() async {
    final active = await _active();
    if (await active.exists()) await active.delete(recursive: true);
  }

  Future<Directory> _active() async =>
      Directory(p.join((await _root()).path, 'active'));

  Future<void> _verify(
    LocalTextModelManifest manifest,
    Directory directory,
  ) async {
    final file = File(p.join(directory.path, manifest.modelFile));
    if (!await file.exists() || await file.length() != manifest.sizeBytes) {
      throw const LocalTextModelPackageException('文本模型文件缺失或大小不正确');
    }
    final actual = (await sha256.bind(file.openRead()).first).toString();
    if (actual.toLowerCase() != manifest.sha256.toLowerCase()) {
      throw const LocalTextModelPackageException('文本模型校验失败');
    }
  }
}

class LocalTextModelPackageException implements Exception {
  final String message;
  const LocalTextModelPackageException(this.message);
  @override
  String toString() => message;
}
