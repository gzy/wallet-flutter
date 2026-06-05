import '../../data/local/app_local_cache.dart';

/// 各业务模块「是否显示后台浮窗」的本地持久化。
class BackendFloatSettingsStore {
  BackendFloatSettingsStore(this._cache);

  final AppLocalCache? _cache;

  Future<bool?> readEnabled(String moduleId) async {
    return _cache?.getBackendFloatEnabled(moduleId);
  }

  Future<void> writeEnabled(String moduleId, bool enabled) async {
    await _cache?.putBackendFloatEnabled(moduleId, enabled);
  }
}
