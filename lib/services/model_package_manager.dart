import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum LocalModelPackageStatus {
  unavailable,
  checking,
  downloading,
  verifying,
  ready,
  failed,
}

class ModelPackageFile {
  final String path;
  final int sizeBytes;
  final String sha256;

  const ModelPackageFile({
    required this.path,
    required this.sizeBytes,
    required this.sha256,
  });

  factory ModelPackageFile.fromJson(Map<String, Object?> json) =>
      ModelPackageFile(
        path: json['path'] as String? ?? '',
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        sha256: json['sha256'] as String? ?? '',
      );
}

class ModelPackageManifest {
  final String id;
  final String version;
  final String architectureVersion;
  final String embeddingVersion;
  final int vectorDimensions;
  final String outputName;
  final List<String> inputNames;
  final int maxLength;
  final List<ModelPackageFile> files;
  final String license;

  const ModelPackageManifest({
    required this.id,
    required this.version,
    required this.architectureVersion,
    required this.embeddingVersion,
    required this.vectorDimensions,
    required this.outputName,
    required this.inputNames,
    required this.maxLength,
    required this.files,
    required this.license,
  });

  int get totalBytes => files.fold(0, (sum, file) => sum + file.sizeBytes);

  ModelPackageFile fileNamed(String name) => files.firstWhere(
    (file) => file.path == name,
    orElse: () => throw StateError('模型清单缺少 $name'),
  );

  factory ModelPackageManifest.fromJson(Map<String, Object?> json) {
    final files = (json['files'] as List<Object?>? ?? const [])
        .whereType<Map<String, Object?>>()
        .map(ModelPackageFile.fromJson)
        .toList(growable: false);
    final architecture = (json['architecture'] as Map?)
        ?.cast<String, Object?>();
    final tokenizer = (json['tokenizer'] as Map?)?.cast<String, Object?>();
    // Accept the original flat beta manifest while packages published by the
    // release tool use the nested architecture/tokenizer declarations.
    final manifest = ModelPackageManifest(
      id: json['id'] as String? ?? '',
      version: json['version'] as String? ?? '',
      architectureVersion:
          json['architectureVersion'] as String? ??
          tokenizer?['version'] as String? ??
          '',
      embeddingVersion:
          json['embeddingVersion'] as String? ??
          '${json['id'] ?? ''}@${json['version'] ?? ''}',
      vectorDimensions:
          (architecture?['vectorDimensions'] as num?)?.toInt() ??
          (json['vectorDimensions'] as num?)?.toInt() ??
          0,
      outputName:
          architecture?['outputName'] as String? ??
          json['outputName'] as String? ??
          '',
      inputNames:
          (architecture?['inputNames'] as List<Object?>? ??
                  json['inputNames'] as List<Object?>? ??
                  const [])
              .whereType<String>()
              .toList(growable: false),
      maxLength:
          (architecture?['maxLength'] as num?)?.toInt() ??
          (json['maxLength'] as num?)?.toInt() ??
          512,
      files: files,
      license: json['license'] as String? ?? '',
    );
    manifest.validate();
    return manifest;
  }

  void validate() {
    if (id != ModelPackageManager.packageId ||
        version.isEmpty ||
        architectureVersion.isEmpty ||
        embeddingVersion.isEmpty ||
        vectorDimensions != 512 ||
        outputName.isEmpty ||
        !inputNames.contains('input_ids') ||
        !inputNames.contains('attention_mask') ||
        maxLength < 2 ||
        maxLength > 512 ||
        files.isEmpty ||
        license.isEmpty) {
      throw const FormatException('Sumi 本地模型清单无效');
    }
    for (final file in files) {
      if (file.path.isEmpty ||
          file.path.contains('..') ||
          file.sizeBytes <= 0 ||
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(file.sha256)) {
        throw const FormatException('Sumi 本地模型文件清单无效');
      }
    }
    fileNamed('model.onnx');
    fileNamed('tokenizer/vocab.txt');
  }
}

/// A verified package which is not active yet. The coordinator loads this
/// directory first, so a broken upgrade never replaces the working model.
class ModelPackageCandidate {
  const ModelPackageCandidate({
    required this.manifest,
    required this.directory,
  });

  final ModelPackageManifest manifest;
  final Directory directory;
}

class ModelPackageProgress {
  final LocalModelPackageStatus status;
  final int receivedBytes;
  final int totalBytes;
  final String? message;

  const ModelPackageProgress({
    required this.status,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.message,
  });
}

/// Downloads only Sumi's fixed, verified ModelScope package. It has no API for
/// arbitrary URLs, so local retrieval cannot become a content upload path.
class ModelPackageManager {
  static const packageId = 'Hilith/bge-small-zh-v1.5-onnx-int8';
  // ModelScope creates this repository with `master` as its default branch.
  static const _revision = 'master';
  static const _manifestPath = 'manifest.json';
  static const _modelFile = 'model.onnx';
  static const _vocabFile = 'tokenizer/vocab.txt';

  final http.Client _client;
  final bool _ownsClient;
  final Future<Directory> Function() _directory;

  ModelPackageManager({
    http.Client? client,
    Future<Directory> Function()? directory,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _directory = directory ?? _defaultDirectory;

  static Future<Directory> _defaultDirectory() async {
    final root = await getApplicationSupportDirectory();
    return Directory(p.join(root.path, 'sumi', 'models', packageId));
  }

  Uri _urlFor(String path) => Uri.parse(
    'https://modelscope.ai/models/$packageId/resolve/$_revision/$path',
  );

  Future<ModelPackageManifest> fetchManifest() async {
    final response = await _client
        .get(_urlFor(_manifestPath))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw ModelPackageException('模型包暂未发布或无法访问（HTTP ${response.statusCode}）');
    }
    try {
      return ModelPackageManifest.fromJson(
        (jsonDecode(response.body) as Map).cast<String, Object?>(),
      );
    } catch (error) {
      if (error is ModelPackageException || error is FormatException) rethrow;
      throw const ModelPackageException('模型清单解析失败');
    }
  }

  Future<ModelPackageManifest?> installedManifest() async {
    final dir = await _activeDirectory();
    final file = File(p.join(dir.path, _manifestPath));
    if (!await file.exists()) return null;
    try {
      final manifest = ModelPackageManifest.fromJson(
        (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>(),
      );
      await verify(manifest, directory: dir);
      return manifest;
    } catch (_) {
      return null;
    }
  }

  Future<ModelPackageCandidate> download({
    required void Function(ModelPackageProgress progress) onProgress,
    Future<bool> Function()? isCancelled,
  }) async {
    onProgress(
      const ModelPackageProgress(status: LocalModelPackageStatus.checking),
    );
    final manifest = await fetchManifest();
    final root = await _directory();
    final dir = Directory(
      p.join(root.path, '.staging-${manifest.embeddingVersion}'),
    );
    await dir.create(recursive: true);
    var completed = 0;
    for (final file in manifest.files) {
      if (await isCancelled?.call() ?? false) {
        throw const ModelPackageException('下载已取消');
      }
      await _downloadFile(
        dir: dir,
        file: file,
        baseCompleted: completed,
        total: manifest.totalBytes,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
      completed += file.sizeBytes;
    }
    onProgress(
      ModelPackageProgress(
        status: LocalModelPackageStatus.verifying,
        receivedBytes: manifest.totalBytes,
        totalBytes: manifest.totalBytes,
      ),
    );
    try {
      await verify(manifest, directory: dir);
      await File(p.join(dir.path, _manifestPath)).writeAsString(
        jsonEncode({
          'id': manifest.id,
          'version': manifest.version,
          'architectureVersion': manifest.architectureVersion,
          'embeddingVersion': manifest.embeddingVersion,
          'vectorDimensions': manifest.vectorDimensions,
          'outputName': manifest.outputName,
          'inputNames': manifest.inputNames,
          'maxLength': manifest.maxLength,
          'license': manifest.license,
          'files': manifest.files
              .map(
                (file) => {
                  'path': file.path,
                  'sizeBytes': file.sizeBytes,
                  'sha256': file.sha256,
                },
              )
              .toList(),
        }),
      );
      return ModelPackageCandidate(manifest: manifest, directory: dir);
    } catch (_) {
      // A cancelled transfer remains in staging and resumes with HTTP Range on
      // the next attempt. Integrity failures still remove the bad package.
      if (!await (isCancelled?.call() ?? Future.value(false)) &&
          await dir.exists()) {
        await dir.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<void> activate(ModelPackageCandidate candidate) async {
    final active = await _activeDirectory();
    final backup = Directory('${active.path}.previous');
    if (await backup.exists()) await backup.delete(recursive: true);
    if (await active.exists()) await active.rename(backup.path);
    try {
      await candidate.directory.rename(active.path);
      if (await backup.exists()) await backup.delete(recursive: true);
    } catch (_) {
      if (!await active.exists() && await backup.exists()) {
        await backup.rename(active.path);
      }
      rethrow;
    }
  }

  Future<void> discard(ModelPackageCandidate candidate) async {
    if (await candidate.directory.exists()) {
      await candidate.directory.delete(recursive: true);
    }
  }

  Future<void> _downloadFile({
    required Directory dir,
    required ModelPackageFile file,
    required int baseCompleted,
    required int total,
    required void Function(ModelPackageProgress) onProgress,
    Future<bool> Function()? isCancelled,
  }) async {
    final target = File(p.join(dir.path, file.path));
    await target.parent.create(recursive: true);
    var existing = await target.exists() ? await target.length() : 0;
    if (existing > file.sizeBytes) {
      await target.delete();
      existing = 0;
    }
    if (existing == file.sizeBytes && await _matchesHash(target, file.sha256)) {
      return;
    }
    if (existing == file.sizeBytes) {
      await target.delete();
      existing = 0;
    }
    final request = http.Request('GET', _urlFor(file.path));
    if (existing > 0) request.headers['Range'] = 'bytes=$existing-';
    final response = await _client
        .send(request)
        .timeout(const Duration(minutes: 5));
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw ModelPackageException('模型文件下载失败（HTTP ${response.statusCode}）');
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
        if (await isCancelled?.call() ?? false) {
          throw const ModelPackageException('下载已取消');
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress(
          ModelPackageProgress(
            status: LocalModelPackageStatus.downloading,
            receivedBytes: baseCompleted + received,
            totalBytes: total,
          ),
        );
      }
    } finally {
      await sink.close();
    }
    if (received != file.sizeBytes ||
        !await _matchesHash(target, file.sha256)) {
      throw const ModelPackageException('模型文件校验失败');
    }
  }

  Future<void> verify(
    ModelPackageManifest manifest, {
    Directory? directory,
  }) async {
    final dir = directory ?? await _activeDirectory();
    for (final file in manifest.files) {
      final target = File(p.join(dir.path, file.path));
      if (!await target.exists() ||
          await target.length() != file.sizeBytes ||
          !await _matchesHash(target, file.sha256)) {
        throw const ModelPackageException('模型文件缺失或校验失败');
      }
    }
  }

  Future<String> modelPath() async =>
      p.join((await _activeDirectory()).path, _modelFile);
  Future<String> vocabPath() async =>
      p.join((await _activeDirectory()).path, _vocabFile);
  String modelPathIn(Directory directory) => p.join(directory.path, _modelFile);
  String vocabPathIn(Directory directory) => p.join(directory.path, _vocabFile);

  Future<void> delete() async {
    final dir = await _activeDirectory();
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<Directory> _activeDirectory() async =>
      Directory(p.join((await _directory()).path, 'active'));

  Future<bool> _matchesHash(File file, String expected) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == expected.toLowerCase();
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class ModelPackageException implements Exception {
  final String message;
  const ModelPackageException(this.message);
  @override
  String toString() => message;
}
