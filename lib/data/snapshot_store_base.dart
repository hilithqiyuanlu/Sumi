/// 快照持久化抽象接口。

abstract class SumiSnapshotStore {
  Future<Map<String, Object?>?> readSnapshot();
  Future<void> writeSnapshot(Map<String, Object?> snapshot);
  Future<String> exportSnapshotText();
  Future<void> importSnapshotText(String text);
}
