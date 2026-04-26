import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

import '../wallet/secure_storage_service.dart';

class InstallGuard {
  static const String _markerFileName = '.install_marker_v1';
  static const Duration _kGuardTimeout = Duration(seconds: 2);

  /// iOS 的 Keychain 默认不会随卸载清空。
  /// 这里通过“沙盒 marker 文件是否存在”来判断是否为重装后的首次启动：
  /// - marker 不存在：视为新装/重装，先清理钱包 key，再写入 marker
  /// - marker 存在：正常启动，不做任何清理
  static Future<void> purgeWalletSecretsOnFreshInstall() async {
    final sw = Stopwatch()..start();
    final dir = await getApplicationSupportDirectory().timeout(_kGuardTimeout);
    final marker = File('${dir.path}/$_markerFileName');
    final exists = await marker.exists().timeout(_kGuardTimeout);
    if (exists) {
      if (kDebugMode) {
        debugPrint('InstallGuard: marker exists, skip purge (${sw.elapsedMilliseconds}ms)');
      }
      return;
    }

    if (kDebugMode) {
      debugPrint('InstallGuard: fresh install detected, purging wallet keys...');
    }
    await SecureStorageService()
        .purgeWalletKeysForFreshInstall()
        .timeout(_kGuardTimeout);

    await dir.create(recursive: true).timeout(_kGuardTimeout);
    await marker.writeAsString(
      DateTime.now().toIso8601String(),
      flush: true,
    ).timeout(_kGuardTimeout);

    if (kDebugMode) {
      debugPrint('InstallGuard: purge complete (${sw.elapsedMilliseconds}ms)');
    }
  }
}

