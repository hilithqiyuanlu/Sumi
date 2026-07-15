import '../data/embedding_document_store.dart';
import 'embedding_indexer.dart';
import 'local_embedding_runtime.dart';
import 'local_embedding_service.dart';
import 'model_package_manager.dart';

class LocalRetrievalState {
  final LocalModelPackageStatus packageStatus;
  final String? version;
  final String? indexVersion;
  final int downloadedBytes;
  final int totalBytes;
  final EmbeddingIndexProgress indexProgress;
  final String? error;

  const LocalRetrievalState({
    this.packageStatus = LocalModelPackageStatus.unavailable,
    this.version,
    this.indexVersion,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.indexProgress = const EmbeddingIndexProgress(
      completed: 0,
      total: 0,
      running: false,
    ),
    this.error,
  });

  LocalRetrievalState copyWith({
    LocalModelPackageStatus? packageStatus,
    String? version,
    String? indexVersion,
    int? downloadedBytes,
    int? totalBytes,
    EmbeddingIndexProgress? indexProgress,
    String? error,
    bool clearError = false,
    bool clearIndexVersion = false,
  }) => LocalRetrievalState(
    packageStatus: packageStatus ?? this.packageStatus,
    version: version ?? this.version,
    indexVersion: clearIndexVersion ? null : indexVersion ?? this.indexVersion,
    downloadedBytes: downloadedBytes ?? this.downloadedBytes,
    totalBytes: totalBytes ?? this.totalBytes,
    indexProgress: indexProgress ?? this.indexProgress,
    error: clearError ? null : error ?? this.error,
  );
}

class LocalRetrievalCoordinator {
  final ModelPackageManager packages;
  final LocalEmbeddingRuntime runtime;
  final LocalEmbeddingService embedding;
  final EmbeddingDocumentStore documents;
  final EmbeddingIndexer indexer;
  final void Function(LocalRetrievalState state) _onState;
  LocalRetrievalState _state = const LocalRetrievalState();
  bool _cancelled = false;

  LocalRetrievalCoordinator({
    required this.packages,
    required this.runtime,
    required this.embedding,
    required this.documents,
    required this.indexer,
    required void Function(LocalRetrievalState state) stateListener,
  }) : _onState = stateListener;

  LocalRetrievalState get state => _state;

  Future<void> restore() async {
    String? version;
    try {
      final manifest = await packages.installedManifest();
      if (manifest == null) {
        _emit(const LocalRetrievalState());
        return;
      }
      version = manifest.version;
      await embedding.load(
        modelPath: await packages.modelPath(),
        vocabPath: await packages.vocabPath(),
        embeddingVersion: manifest.embeddingVersion,
        outputName: manifest.outputName,
        inputNames: manifest.inputNames,
        maxLength: manifest.maxLength,
      );
      _emit(
        LocalRetrievalState(
          packageStatus: LocalModelPackageStatus.ready,
          version: version,
          indexVersion: await _matchingIndexVersion(embedding.embeddingVersion),
        ),
      );
      _startIndexing();
    } catch (error) {
      _emit(
        LocalRetrievalState(
          packageStatus: LocalModelPackageStatus.failed,
          version: version,
          error: error.toString(),
        ),
      );
    }
  }

  Future<void> download() async {
    _cancelled = false;
    final device = await runtime.checkDevice();
    if (!device.isSupported) {
      _emit(
        _state.copyWith(
          packageStatus: LocalModelPackageStatus.failed,
          error: device.reason ?? '此设备不支持本地语义检索',
        ),
      );
      return;
    }
    ModelPackageManifest? previousManifest;
    ModelPackageCandidate? candidate;
    try {
      final expected = await packages.fetchManifest();
      if (device.freeBytes < expected.totalBytes * 2) {
        throw const ModelPackageException('存储空间不足，至少需要模型包两倍的可用空间');
      }
      previousManifest = await packages.installedManifest();
      final oldVersion = embedding.embeddingVersion;
      final preparedCandidate = await packages.download(
        isCancelled: () async => _cancelled,
        onProgress: (progress) {
          _emit(
            _state.copyWith(
              packageStatus: progress.status,
              downloadedBytes: progress.receivedBytes,
              totalBytes: progress.totalBytes,
              error: progress.message,
              clearError: progress.message == null,
              clearIndexVersion: true,
            ),
          );
        },
      );
      candidate = preparedCandidate;
      final manifest = preparedCandidate.manifest;
      await embedding.load(
        modelPath: packages.modelPathIn(preparedCandidate.directory),
        vocabPath: packages.vocabPathIn(preparedCandidate.directory),
        embeddingVersion: manifest.embeddingVersion,
        outputName: manifest.outputName,
        inputNames: manifest.inputNames,
        maxLength: manifest.maxLength,
      );
      await packages.activate(preparedCandidate);
      if (oldVersion != null && oldVersion != manifest.embeddingVersion) {
        await documents.clear();
      }
      _emit(
        _state.copyWith(
          packageStatus: LocalModelPackageStatus.ready,
          version: manifest.version,
          indexVersion: null,
          downloadedBytes: manifest.totalBytes,
          totalBytes: manifest.totalBytes,
          clearError: true,
        ),
      );
      _startIndexing();
    } catch (error) {
      // Loading a candidate replaces the native ONNX session. Reload the
      // verified active package before reporting the failed upgrade so the
      // existing local index remains usable.
      if (previousManifest != null) {
        try {
          await embedding.load(
            modelPath: await packages.modelPath(),
            vocabPath: await packages.vocabPath(),
            embeddingVersion: previousManifest.embeddingVersion,
            outputName: previousManifest.outputName,
            inputNames: previousManifest.inputNames,
            maxLength: previousManifest.maxLength,
          );
        } catch (_) {
          // The original error remains the useful user-facing failure.
        }
      }
      if (candidate case final failedCandidate?) {
        await packages.discard(failedCandidate);
      }
      _emit(
        _state.copyWith(
          packageStatus: LocalModelPackageStatus.failed,
          error: error.toString(),
        ),
      );
    }
  }

  void cancel() {
    _cancelled = true;
    indexer.cancel();
  }

  Future<void> deleteModel() async {
    cancel();
    await runtime.unload();
    await packages.delete();
    await documents.clear();
    _emit(const LocalRetrievalState());
  }

  Future<void> recheck() => restore();

  Future<void> rebuildIndex() => _startIndexing();

  Future<void> _startIndexing() async {
    await indexer.rebuildAll(
      onProgress: (progress) {
        _emit(
          _state.copyWith(
            indexProgress: progress,
            indexVersion: progress.running ? null : embedding.embeddingVersion,
            clearIndexVersion: progress.running,
          ),
        );
      },
    );
  }

  Future<String?> _matchingIndexVersion(String? modelVersion) async {
    if (modelVersion == null || modelVersion.isEmpty) return null;
    final versions = await documents.embeddingVersions();
    return versions.isEmpty ||
            (versions.length == 1 && versions.single == modelVersion)
        ? modelVersion
        : null;
  }

  Future<void> close() async {
    cancel();
    await runtime.unload();
    packages.close();
  }

  void _emit(LocalRetrievalState state) {
    _state = state;
    _onState(state);
  }
}
