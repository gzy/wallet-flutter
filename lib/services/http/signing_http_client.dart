import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'http_request_timing.dart';
import 'http_signature.dart';

/// 对与当前 [kWalletApiBase] 同 host 的请求附加 `X-Sign` 等 Header（见 HttpSignature 文档）。
class SigningHttpClient extends http.BaseClient {
  SigningHttpClient(this._inner);

  final http.Client _inner;

  static const bool _closeConnectionOnWalletHost = bool.fromEnvironment(
    'WALLET_HTTP_CLOSE_CONNECTION',
    defaultValue: true,
  );

  static bool _isWalletApiHost(String host) {
    final expected = Uri.parse(kWalletApiBase).host;
    return expected.isNotEmpty &&
        host.toLowerCase() == expected.toLowerCase();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!kDebugMode) {
      final prepared = await _prepare(request, null);
      return _inner.send(prepared);
    }

    final timing = httpRequestTimingFor(request);
    final prepareSw = Stopwatch()..start();
    final prepared = await _prepare(request, timing);
    timing.prepareMs = prepareSw.elapsedMilliseconds;

    final networkSw = Stopwatch()..start();
    final response = await _inner.send(prepared);
    timing.networkMs = networkSw.elapsedMilliseconds;
    return response;
  }

  Future<http.BaseRequest> _prepare(
    http.BaseRequest request,
    HttpRequestTiming? timing,
  ) async {
    if (_closeConnectionOnWalletHost && _isWalletApiHost(request.url.host)) {
      request.headers['connection'] = 'close';
    }
    if (!httpSignatureAppliesToHost(request.url.host)) {
      return request;
    }

    if (request is http.Request) {
      if (timing != null) {
        final signSw = Stopwatch()..start();
        httpApplySignatureHeaders(request);
        timing.signMs = signSw.elapsedMilliseconds;
      } else {
        httpApplySignatureHeaders(request);
      }
      return request;
    }

    if (request is http.StreamedRequest) {
      final bytes = await _collectStream(request.finalize());
      final r = http.Request(request.method, request.url);
      r.headers.addAll(request.headers);
      r.headers.removeWhere((k, _) => k.toLowerCase() == 'content-length');
      r.bodyBytes = bytes;
      if (timing != null) {
        final signSw = Stopwatch()..start();
        httpApplySignatureHeaders(r);
        timing.signMs = signSw.elapsedMilliseconds;
      } else {
        httpApplySignatureHeaders(r);
      }
      return r;
    }

    return request;
  }

  static Future<Uint8List> _collectStream(Stream<List<int>> stream) async {
    final chunks = await stream.toList();
    var length = 0;
    for (final c in chunks) {
      length += c.length;
    }
    final out = Uint8List(length);
    var offset = 0;
    for (final c in chunks) {
      out.setRange(offset, offset + c.length, c);
      offset += c.length;
    }
    return out;
  }

  @override
  void close() {
    _inner.close();
  }
}
