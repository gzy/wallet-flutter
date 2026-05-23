import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'spki_pinning.dart';

class PinnedHttpClient {
  PinnedHttpClient({
    required Map<String, List<String>> pinsByHost,
    http.Client? fallback,
  })  : _pinsByHost = _normalizePins(pinsByHost),
        _fallback = fallback ?? http.Client(),
        _pinned = IOClient(_buildPinnedIoClient(_normalizePins(pinsByHost)));

  final Map<String, List<String>> _pinsByHost;
  final http.Client _fallback;
  final http.Client _pinned;

  http.Client clientForHost(String host) {
    return _pinsByHost.containsKey(host) ? _pinned : _fallback;
  }

  void close() {
    _pinned.close();
    _fallback.close();
  }

  static Map<String, List<String>> _normalizePins(
    Map<String, List<String>> pinsByHost,
  ) {
    return {
      for (final e in pinsByHost.entries)
        e.key.trim().toLowerCase(): e.value.where((p) => p.trim().isNotEmpty).toList(),
    };
  }

  static HttpClient _buildPinnedIoClient(Map<String, List<String>> pinsByHost) {
    // 先走系统 CA 校验；再额外执行 SPKI pin 校验（失败则拒绝）。
    // 这样可以避免因为证书解析差异导致的“所有连接都走 badCertificateCallback”不稳定问题。
    final io = HttpClient();

    // 略短于常见网关 idle，减少「服务端已关连接、客户端仍复用」导致的
    // WRONG_VERSION_NUMBER / 握手异常（并行余额请求时更明显）。
    io.idleTimeout = const Duration(seconds: 10);

    io.badCertificateCallback = (cert, host, port) {
      try {
        final pins = pinsByHost[host.trim().toLowerCase()];
        if (pins == null || pins.isEmpty) {
          // 没配置 pin 的 host，不在这里放行（维持系统默认：证书坏就拒绝）。
          return false;
        }
        final got = SpkiPinning.spkiSha256Base64FromPem(cert.pem);
        return pins.contains(got);
      } catch (_) {
        return false;
      }
    };

    return io;
  }
}

