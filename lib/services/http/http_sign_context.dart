/// [HttpSignatureInit] 在应用启动时写入；供 [SigningHttpClient] 填充 Header。
class HttpSignContext {
  HttpSignContext._();

  /// 持久化在 Secure Storage，跨会话稳定。
  static String deviceId = '';

  /// `package_info` 的 version + build。
  static String appVersion = '0.0.0';

  /// 与后端约定的应用标识。
  static const String appId = 'uone-wallet';
}
