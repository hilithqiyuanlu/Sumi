import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// API Key 安全存储 —— 与 JSON 快照分离。
class SecureSettingsStore {
  static const _deepseekKey = 'sumi.deepseekApiKey';
  static const _tavilyKey = 'sumi.tavilyApiKey';

  final FlutterSecureStorage _storage;

  SecureSettingsStore()
      : _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );

  Future<String> readDeepseekApiKey() async {
    try {
      return await _storage.read(key: _deepseekKey) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> writeDeepseekApiKey(String key) async {
    try {
      await _storage.write(key: _deepseekKey, value: key);
    } catch (_) {
      // 安全存储不可用时静默失败
    }
  }

  Future<String> readTavilyApiKey() async {
    try {
      return await _storage.read(key: _tavilyKey) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> writeTavilyApiKey(String key) async {
    try {
      await _storage.write(key: _tavilyKey, value: key);
    } catch (_) {
      // 安全存储不可用时静默失败
    }
  }

  Future<void> clearAll() async {
    try {
      await _storage.deleteAll();
    } catch (_) {}
  }
}
