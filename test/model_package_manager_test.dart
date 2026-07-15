import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sumi/services/model_package_manager.dart';

String _hash(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  test('新模型先保留为候选包，激活后才替换旧模型', () async {
    final root = await Directory.systemTemp.createTemp('sumi-model-test-');
    addTearDown(() => root.delete(recursive: true));
    final model = utf8.encode('new-model');
    final vocab = utf8.encode('[PAD]\n[UNK]\n[CLS]\n[SEP]\n学\n习\n');
    final manifest = <String, Object?>{
      'id': ModelPackageManager.packageId,
      'version': '1.0.0',
      'architectureVersion': 'sumi-bge-wordpiece-1',
      'embeddingVersion': '${ModelPackageManager.packageId}@1.0.0',
      'architecture': {
        'inputNames': ['input_ids', 'attention_mask', 'token_type_ids'],
        'outputName': 'sentence_embedding',
        'vectorDimensions': 512,
        'maxLength': 512,
      },
      'tokenizer': {'format': 'huggingface-wordpiece', 'version': '1'},
      'license': 'MIT',
      'files': [
        {
          'path': 'model.onnx',
          'sizeBytes': model.length,
          'sha256': _hash(model),
        },
        {
          'path': 'tokenizer/vocab.txt',
          'sizeBytes': vocab.length,
          'sha256': _hash(vocab),
        },
      ],
    };
    final client = MockClient((request) async {
      final requested = request.url.path.split('/resolve/master/').last;
      expect(
        request.url.path,
        '/models/${ModelPackageManager.packageId}/resolve/master/$requested',
      );
      if (requested == 'manifest.json') {
        return http.Response(jsonEncode(manifest), 200);
      }
      if (requested == 'model.onnx') {
        return http.Response.bytes(model, 200);
      }
      if (requested == 'tokenizer/vocab.txt') {
        return http.Response.bytes(vocab, 200);
      }
      return http.Response('', 404);
    });
    final manager = ModelPackageManager(
      client: client,
      directory: () async => root,
    );
    final active = Directory(p.join(root.path, 'active'));
    await active.create(recursive: true);
    await File(p.join(active.path, 'old.txt')).writeAsString('working');

    final candidate = await manager.download(onProgress: (_) {});

    expect(
      await File(p.join(active.path, 'old.txt')).readAsString(),
      'working',
    );
    expect(
      await File(p.join(candidate.directory.path, 'model.onnx')).exists(),
      isTrue,
    );
    await manager.activate(candidate);
    expect(await File(p.join(active.path, 'model.onnx')).exists(), isTrue);
    expect(await File(p.join(active.path, 'old.txt')).exists(), isFalse);
  });

  test('拒绝缺少真实模型结构声明的清单', () {
    expect(
      () => ModelPackageManifest.fromJson({
        'id': ModelPackageManager.packageId,
        'version': '1.0.0',
        'architectureVersion': 'sumi-bge-wordpiece-1',
        'embeddingVersion': 'test',
        'license': 'MIT',
        'files': const [],
      }),
      throwsFormatException,
    );
  });
}
