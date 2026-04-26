import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'logging_http_client.dart';
import 'pinned_http_client.dart';
import 'routing_http_client.dart';

class HttpClients {
  // 你提供的 SPKI pin（Base64(SHA256(SPKI))）。
  // 建议至少再加一条“备用 key”的 pin 以支持未来轮换。
  static const String _kUoneTestApiSpkiPin =
      'OProKNBaOVzvoyeZXhHYupQ+59Z2GYgQhWug3xY3/S0=';

  static final Map<String, List<String>> _pinsByHost = {
    // 测试环境
    'api-wallet-test.uone.me': const [
      _kUoneTestApiSpkiPin,
      // TODO: 备用 key pin 放这里
    ],
  };

  static final PinnedHttpClient _pinned = PinnedHttpClient(
    pinsByHost: _pinsByHost,
  );

  static http.Client create({
    required String logName,
    int maxLogBodyLength = 16000,
    bool enableLoggingInDebug = true,
  }) {
    final base = RoutingHttpClient(_pinned);
    if (kDebugMode && enableLoggingInDebug) {
      return LoggingHttpClient(
        base,
        logName: logName,
        maxLogBodyLength: maxLogBodyLength,
      );
    }
    return base;
  }
}

