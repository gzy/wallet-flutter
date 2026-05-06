import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../wallet/apple_secure_storage_options.dart';
import 'http_sign_context.dart';

/// 启动时调用一次：设备 ID（持久化）、应用版本（展示于 X-App-Version）。
class HttpSignatureInit {
  HttpSignatureInit._();

  static const _kDeviceKey = 'http_sign_device_id_v1';

  static const IOSOptions _iosOptions = AppleSecureStorageOptions.ios;

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    iOptions: AppleSecureStorageOptions.ios,
    mOptions: AppleSecureStorageOptions.macOs,
  );

  static Future<void>? _pending;
  static bool _ready = false;

  static Future<void> ensureInitialized() {
    if (_ready) return Future.value();
    _pending ??= _load();
    return _pending!;
  }

  static Future<void> _load() async {
    try {
      if (kIsWeb) {
        HttpSignContext.deviceId = 'web-${const Uuid().v4()}';
        HttpSignContext.appVersion = 'web';
        _ready = true;
        return;
      }

      final info = await PackageInfo.fromPlatform();
      HttpSignContext.appVersion = '${info.version}+${info.buildNumber}';

      var id = await _storage.read(key: _kDeviceKey, iOptions: _iosOptions);
      if (id == null || id.isEmpty) {
        id = const Uuid().v4();
        await _storage.write(
          key: _kDeviceKey,
          value: id,
          iOptions: _iosOptions,
        );
      }
      HttpSignContext.deviceId = id;
      _ready = true;
    } catch (e, st) {
      debugPrint('HttpSignatureInit: fallback device id ($e)\n$st');
      HttpSignContext.deviceId = HttpSignContext.deviceId.isNotEmpty
          ? HttpSignContext.deviceId
          : const Uuid().v4();
      _ready = true;
    }
  }
}
