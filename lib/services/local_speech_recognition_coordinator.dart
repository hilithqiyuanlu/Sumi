import 'local_speech_model_package.dart';
import 'local_speech_recognition_runtime.dart';

enum LocalSpeechModelStatus {
  unavailable,
  checking,
  downloading,
  loading,
  ready,
  failed,
}

class LocalSpeechModelState {
  const LocalSpeechModelState({
    this.status = LocalSpeechModelStatus.unavailable,
    this.version,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.error,
  });
  final LocalSpeechModelStatus status;
  final String? version;
  final int receivedBytes;
  final int totalBytes;
  final String? error;
}

class LocalSpeechRecognitionCoordinator {
  LocalSpeechRecognitionCoordinator({
    required this.packages,
    required this.runtime,
    required this.onState,
  });

  final LocalSpeechModelPackage packages;
  final LocalSpeechRecognitionRuntime runtime;
  final void Function(LocalSpeechModelState state) onState;
  LocalSpeechModelState _state = const LocalSpeechModelState();
  LocalSpeechModelState get state => _state;

  Future<void> restore() async {
    try {
      final manifest = await packages.installedManifest();
      if (manifest == null) return _emit(const LocalSpeechModelState());
      await runtime.load(
        modelPath: await packages.modelPath(),
        tokensPath: await packages.tokensPath(),
        version: manifest.version,
      );
      _emit(
        LocalSpeechModelState(
          status: LocalSpeechModelStatus.ready,
          version: manifest.version,
        ),
      );
    } catch (error) {
      _emit(
        LocalSpeechModelState(
          status: LocalSpeechModelStatus.failed,
          error: error.toString(),
        ),
      );
    }
  }

  Future<void> download() async {
    try {
      _emit(
        const LocalSpeechModelState(status: LocalSpeechModelStatus.checking),
      );
      final manifest = await packages.fetchManifest();
      final candidate = await packages.download(
        manifest,
        onProgress: (received, total) => _emit(
          LocalSpeechModelState(
            status: LocalSpeechModelStatus.downloading,
            version: manifest.version,
            receivedBytes: received,
            totalBytes: total,
          ),
        ),
      );
      _emit(
        LocalSpeechModelState(
          status: LocalSpeechModelStatus.loading,
          version: manifest.version,
        ),
      );
      await runtime.load(
        modelPath: '${candidate.path}/model.int8.onnx',
        tokensPath: '${candidate.path}/tokens.txt',
        version: manifest.version,
      );
      await packages.activate(candidate);
      _emit(
        LocalSpeechModelState(
          status: LocalSpeechModelStatus.ready,
          version: manifest.version,
          receivedBytes: manifest.totalBytes,
          totalBytes: manifest.totalBytes,
        ),
      );
    } catch (error) {
      _emit(
        LocalSpeechModelState(
          status: LocalSpeechModelStatus.failed,
          error: error.toString(),
        ),
      );
    }
  }

  Future<void> delete() async {
    await runtime.unload();
    await packages.delete();
    _emit(const LocalSpeechModelState());
  }

  Future<void> close() => runtime.unload();

  void _emit(LocalSpeechModelState value) {
    _state = value;
    onState(value);
  }
}
