import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sumi/services/local_speech_model_package.dart';

String _hash(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  test('语音模型下载校验后才替换旧包', () async {
    final root = await Directory.systemTemp.createTemp('sumi-speech-model-');
    addTearDown(() => root.delete(recursive: true));
    final model = utf8.encode('sensevoice-int8-model');
    final tokens = utf8.encode('<blank> 0\n你 1\nhello 2\n');
    final manifest = <String, Object?>{
      'id': LocalSpeechModelPackage.repositoryId,
      'version': '1.0.0',
      'runtime': 'sherpa-onnx-sensevoice',
      'files': [
        {
          'path': 'model.int8.onnx',
          'sizeBytes': model.length,
          'sha256': _hash(model),
        },
        {
          'path': 'tokens.txt',
          'sizeBytes': tokens.length,
          'sha256': _hash(tokens),
        },
      ],
    };
    final manager = LocalSpeechModelPackage(
      root: () async => root,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/manifest.json')) {
          return http.Response(jsonEncode(manifest), 200);
        }
        if (request.url.path.endsWith('/model.int8.onnx')) {
          return http.Response.bytes(model, 200);
        }
        if (request.url.path.endsWith('/tokens.txt')) {
          return http.Response.bytes(tokens, 200);
        }
        return http.Response('', 404);
      }),
    );
    final active = Directory(p.join(root.path, 'active'));
    await active.create(recursive: true);
    await File(p.join(active.path, 'old-model')).writeAsString('working');

    final parsed = await manager.fetchManifest();
    final candidate = await manager.download(parsed, onProgress: (_, _) {});

    expect(await File(p.join(active.path, 'old-model')).exists(), isTrue);
    await manager.activate(candidate);
    expect(await File(p.join(active.path, 'old-model')).exists(), isFalse);
    expect(
      await File(p.join(active.path, 'model.int8.onnx')).readAsBytes(),
      model,
    );
    expect((await manager.installedManifest())?.version, '1.0.0');
  });

  test('完整临时文件校验后恢复，不重复请求模型', () async {
    final root = await Directory.systemTemp.createTemp('sumi-speech-resume-');
    addTearDown(() => root.delete(recursive: true));
    final model = utf8.encode('complete-sensevoice');
    final tokens = utf8.encode('tokens');
    final manifest = LocalSpeechModelManifest.fromJson({
      'id': LocalSpeechModelPackage.repositoryId,
      'version': '1.0.0',
      'files': [
        {
          'path': 'model.int8.onnx',
          'sizeBytes': model.length,
          'sha256': _hash(model),
        },
        {
          'path': 'tokens.txt',
          'sizeBytes': tokens.length,
          'sha256': _hash(tokens),
        },
      ],
    });
    final staging = Directory(p.join(root.path, '.staging-1.0.0'));
    await staging.create(recursive: true);
    await File(p.join(staging.path, 'model.int8.onnx')).writeAsBytes(model);
    await File(p.join(staging.path, 'tokens.txt')).writeAsBytes(tokens);
    var requested = false;
    final manager = LocalSpeechModelPackage(
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

  test('拒绝多余或缺失运行文件的清单', () {
    expect(
      () => LocalSpeechModelManifest.fromJson({
        'id': LocalSpeechModelPackage.repositoryId,
        'version': '1.0.0',
        'files': [
          {'path': 'model.int8.onnx', 'sizeBytes': 1, 'sha256': 'a' * 64},
        ],
      }),
      throwsFormatException,
    );
  });

  test('断点响应范围错误时从头重新下载', () async {
    final root = await Directory.systemTemp.createTemp('sumi-speech-range-');
    addTearDown(() => root.delete(recursive: true));
    final model = utf8.encode('complete-sensevoice-model');
    final tokens = utf8.encode('complete-tokens');
    final manifest = LocalSpeechModelManifest.fromJson({
      'id': LocalSpeechModelPackage.repositoryId,
      'version': '1.0.0',
      'files': [
        {
          'path': 'model.int8.onnx',
          'sizeBytes': model.length,
          'sha256': _hash(model),
        },
        {
          'path': 'tokens.txt',
          'sizeBytes': tokens.length,
          'sha256': _hash(tokens),
        },
      ],
    });
    final staging = Directory(p.join(root.path, '.staging-1.0.0'));
    await staging.create(recursive: true);
    await File(
      p.join(staging.path, 'model.int8.onnx'),
    ).writeAsBytes(model.take(4).toList());
    final requests = <http.BaseRequest>[];
    final manager = LocalSpeechModelPackage(
      root: () async => root,
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('model.int8.onnx')) {
          if (request.headers['Range'] != null) {
            return http.Response.bytes(
              model.skip(4).toList(),
              206,
              headers: {
                'content-range': 'bytes 0-${model.length - 5}/${model.length}',
              },
            );
          }
          return http.Response.bytes(model, 200);
        }
        return http.Response.bytes(tokens, 200);
      }),
    );

    final candidate = await manager.download(manifest, onProgress: (_, _) {});

    expect(requests[0].headers['Range'], 'bytes=4-');
    expect(requests[1].headers['Range'], isNull);
    expect(
      await File(p.join(candidate.path, 'model.int8.onnx')).readAsBytes(),
      model,
    );
  });
}
