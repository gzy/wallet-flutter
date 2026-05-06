import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'logging_http_client.dart';
import 'pinned_http_client.dart';
import 'routing_http_client.dart';
import 'signing_http_client.dart';

class HttpClients {
  /// 默认测试环境 SPKI pin（Base64(SHA256(SPKI))）；生产用 `--dart-define=HTTP_PIN_SPKI=...` 覆盖。
  static const String _kDefaultWalletApiSpkiPin =
      'OProKNBaOVzvoyeZXhHYupQ+59Z2GYgQhWug3xY3/S0=';

  /// 与当前 [kWalletApiBase] 的 host 对齐；换环境时请同时配置 `WALLET_API_BASE` 与 pin。
  static Map<String, List<String>> get _pinsByHost {
    final host = Uri.parse(kWalletApiBase).host;
    if (host.isEmpty) {
      return {};
    }
    const pin = String.fromEnvironment(
      'HTTP_PIN_SPKI',
      defaultValue: _kDefaultWalletApiSpkiPin,
    );
    return {
      host: [pin],
    };
  }

  static final PinnedHttpClient _pinned = PinnedHttpClient(
    pinsByHost: _pinsByHost,
  );

  static http.Client create({
    required String logName,
    int maxLogBodyLength = 16000,
    bool enableLoggingInDebug = true,
  }) {
    final routed = RoutingHttpClient(_pinned);
    final signed = SigningHttpClient(routed);
    if (kDebugMode && enableLoggingInDebug) {
      return LoggingHttpClient(
        signed,
        logName: logName,
        maxLogBodyLength: maxLogBodyLength,
      );
    }
    return signed;
  }
}
