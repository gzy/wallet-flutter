import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'http_signature.dart';

/// 对与当前 [kWalletApiBase] 同 host 的请求附加 `X-Sign` 等 Header（见 HttpSignature 文档）。
class SigningHttpClient extends http.BaseClient {
  SigningHttpClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final prepared = await _prepare(request);
    return _inner.send(prepared);
  }

  Future<http.BaseRequest> _prepare(http.BaseRequest request) async {
    if (!httpSignatureAppliesToHost(request.url.host)) {
      return request;
    }

    if (request is http.Request) {
      httpApplySignatureHeaders(request);
      return request;
    }

    if (request is http.StreamedRequest) {
      final bytes = await _collectStream(request.finalize());
      final r = http.Request(request.method, request.url);
      r.headers.addAll(request.headers);
      r.headers.removeWhere((k, _) => k.toLowerCase() == 'content-length');
      r.bodyBytes = bytes;
      httpApplySignatureHeaders(r);
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
