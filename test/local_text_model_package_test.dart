import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sumi/services/local_text_model_package.dart';

void main() {
  test('文本模型下载后校验并安全替换旧包', () async {
    final root = await Directory.systemTemp.createTemp('sumi-text-model-test-');
    addTearDown(() => root.delete(recursive: true));
    final model = utf8.encode('qwen-gguf');
    final manifest = {
      'id': LocalTextModelPackage.repositoryId,
      'version': '1.0.0',
      'runtime': 'gguf',
      'files': [
        {
          'path': 'model.gguf',
          'sizeBytes': model.length,
          'sha256': sha256.convert(model).toString(),
        },
      ],
    };
    final manager = LocalTextModelPackage(
      root: () async => root,
      client: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/manifest.json')) {
          return http.Response(jsonEncode(manifest), 200);
        }
        if (path.endsWith('/model.gguf')) {
          return http.Response.bytes(model, 200);
        }
        return http.Response('', 404);
      }),
    );
    final active = Directory(p.join(root.path, 'active'));
    await active.create(recursive: true);
    await File(p.join(active.path, 'old.gguf')).writeAsString('old');

    final parsed = await manager.fetchManifest();
    final candidate = await manager.download(parsed, onProgress: (_, _) {});
    await manager.activate(candidate);

    expect(await File(p.join(active.path, 'model.gguf')).readAsBytes(), model);
    expect(await File(p.join(active.path, 'old.gguf')).exists(), isFalse);
    expect((await manager.installedManifest())?.version, '1.0.0');
  });

  test('完整临时文件会校验恢复，不发送非法 Range 请求', () async {
    final root = await Directory.systemTemp.createTemp(
      'sumi-text-resume-test-',
    );
    addTearDown(() => root.delete(recursive: true));
    final model = utf8.encode('complete-qwen-gguf');
    final manifest = LocalTextModelManifest(
      id: LocalTextModelPackage.repositoryId,
      version: '1.0.0',
      modelFile: 'model.gguf',
      sizeBytes: model.length,
      sha256: sha256.convert(model).toString(),
    );
    final staging = Directory(p.join(root.path, '.staging-1.0.0'));
    await staging.create(recursive: true);
    await File(p.join(staging.path, 'model.gguf')).writeAsBytes(model);
    var requested = false;
    final manager = LocalTextModelPackage(
      root: () async => root,
      client: MockClient((_) async {
        requested = true;
        return http.Response('', 416);
      }),
    );

    final candidate = await manager.download(manifest, onProgress: (_, _) {});

    expect(candidate.path, staging.path);
    expect(requested, isFalse);
    expect(
      await File(p.join(candidate.path, 'manifest.json')).exists(),
      isTrue,
    );
  });

  test('断点响应范围异常时会自动从头重新下载', () async {
    final root = await Directory.systemTemp.createTemp(
      'sumi-text-range-test-',
    );
    addTearDown(() => root.delete(recursive: true));
    final model = utf8.encode('complete-qwen-gguf');
    final manifest = LocalTextModelManifest(
      id: LocalTextModelPackage.repositoryId,
      version: '1.0.0',
      modelFile: 'model.gguf',
      sizeBytes: model.length,
      sha256: sha256.convert(model).toString(),
    );
    final staging = Directory(p.join(root.path, '.staging-1.0.0'));
    await staging.create(recursive: true);
    await File(p.join(staging.path, 'model.gguf')).writeAsBytes(
      model.take(5).toList(),
    );
    final requests = <http.BaseRequest>[];
    final manager = LocalTextModelPackage(
      root: () async => root,
      client: MockClient((request) async {
        requests.add(request);
        if (request.headers['Range'] != null) {
          return http.Response.bytes(
            model.skip(5).toList(),
            206,
            headers: {'content-range': 'bytes 0-${model.length - 6}/${model.length}'},
          );
        }
        return http.Response.bytes(model, 200);
      }),
    );

    final candidate = await manager.download(manifest, onProgress: (_, _) {});

    expect(requests, hasLength(2));
    expect(requests.first.headers['Range'], 'bytes=5-');
    expect(requests.last.headers['Range'], isNull);
    expect(await File(p.join(candidate.path, 'model.gguf')).readAsBytes(), model);
  });
}
