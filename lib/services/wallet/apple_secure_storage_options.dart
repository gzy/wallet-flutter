import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// [`FlutterSecureStorage`] 在 macOS 上只吃 [MacOsOptions]，传 [IOSOptions] 无效。
///
/// Data Protection Keychain（默认 `true`）在桌面沙盒或未配齐 entitlement 时常报 `-34018`。
abstract final class AppleSecureStorageOptions {
  AppleSecureStorageOptions._();

  static const IOSOptions ios = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
  );

  /// 与 [ios] 对齐；关闭 Data Protection 路径以适配 macOS 调试/桌面构建。
  static const MacOsOptions macOs = MacOsOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
    useDataProtectionKeyChain: false,
  );
}
