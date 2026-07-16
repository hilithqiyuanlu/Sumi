import 'local_text_generation_runtime.dart';
import 'local_text_model_package.dart';

enum LocalTextModelStatus {
  unavailable,
  checking,
  downloading,
  loading,
  ready,
  failed,
}

class LocalTextModelState {
  final LocalTextModelStatus status;
  final String? version;
  final int receivedBytes;
  final int totalBytes;
  final String? error;
  const LocalTextModelState({
    this.status = LocalTextModelStatus.unavailable,
    this.version,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.error,
  });
}

class LocalTextGenerationCoordinator {
  final LocalTextModelPackage packages;
  final LocalTextGenerationRuntime runtime;
  final void Function(LocalTextModelState) onState;
  LocalTextModelState _state = const LocalTextModelState();
  LocalTextModelState get state => _state;

  LocalTextGenerationCoordinator({
    required this.packages,
    required this.runtime,
    required this.onState,
  });

  Future<void> restore() async {
    try {
      final manifest = await packages.installedManifest();
      if (manifest == null) return _emit(const LocalTextModelState());
      await runtime.load(
        modelPath: await packages.modelPath(),
        modelVersion: manifest.version,
      );
      _emit(
        LocalTextModelState(
          status: LocalTextModelStatus.ready,
          version: manifest.version,
        ),
      );
    } catch (error) {
      _emit(
        LocalTextModelState(
          status: LocalTextModelStatus.failed,
          error: error.toString(),
        ),
      );
    }
  }

  Future<void> download() async {
    try {
      _emit(const LocalTextModelState(status: LocalTextModelStatus.checking));
      final manifest = await packages.fetchManifest();
      final candidate = await packages.download(
        manifest,
        onProgress: (received, total) {
          _emit(
            LocalTextModelState(
              status: LocalTextModelStatus.downloading,
              receivedBytes: received,
              totalBytes: total,
            ),
          );
        },
      );
      _emit(
        LocalTextModelState(
          status: LocalTextModelStatus.loading,
          version: manifest.version,
        ),
      );
      await runtime.load(
        modelPath: '${candidate.path}/model.gguf',
        modelVersion: manifest.version,
      );
      await packages.activate(candidate);
      _emit(
        LocalTextModelState(
          status: LocalTextModelStatus.ready,
          version: manifest.version,
          receivedBytes: manifest.sizeBytes,
          totalBytes: manifest.sizeBytes,
        ),
      );
    } catch (error) {
      _emit(
        LocalTextModelState(
          status: LocalTextModelStatus.failed,
          error: error.toString(),
        ),
      );
    }
  }

  Future<void> delete() async {
    await runtime.unload();
    await packages.delete();
    _emit(const LocalTextModelState());
  }

  Future<void> close() async => runtime.unload();
  void _emit(LocalTextModelState value) {
    _state = value;
    onState(value);
  }
}
