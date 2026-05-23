import 'package:http/http.dart' as http;

/// 单次 HTTP 各阶段耗时（Debug 用），挂在 [http.BaseRequest] 上供外层日志读取。
class HttpRequestTiming {
  /// [SigningHttpClient]：验签 Header（HMAC 等）。
  int signMs = 0;

  /// [SigningHttpClient]：整段 `_prepare`（含 StreamedRequest 收 body、Connection 头等）。
  int prepareMs = 0;

  /// [SigningHttpClient]：`await _inner.send` 至收到 [StreamedResponse]（TLS + 往返 + 服务端处理）。
  int networkMs = 0;

  /// [LoggingHttpClient]：读完响应 body。
  int bodyMs = 0;

  int get totalMs => prepareMs + networkMs + bodyMs;

  /// `prepareMs - signMs`，仅在有明显额外准备时展示。
  int get prepareOtherMs {
    final extra = prepareMs - signMs;
    return extra > 0 ? extra : 0;
  }

  String breakdownLabel() {
    final parts = <String>[];
    if (signMs > 0) {
      parts.add('签名 ${signMs}ms');
    }
    final other = prepareOtherMs;
    if (other > 0) {
      parts.add('准备 ${other}ms');
    }
    parts.add('网络 ${networkMs}ms');
    if (bodyMs > 0) {
      parts.add('读体 ${bodyMs}ms');
    }
    return parts.join(' · ');
  }
}

final Expando<HttpRequestTiming> _timingByRequest =
    Expando<HttpRequestTiming>('httpRequestTiming');

HttpRequestTiming httpRequestTimingFor(http.BaseRequest request) {
  return _timingByRequest[request] ??= HttpRequestTiming();
}
