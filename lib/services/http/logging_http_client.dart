import 'dart:convert';
import 'dart:developer' show log;

import 'package:http/http.dart' as http;

/// 包装任意 [http.Client]，在 [enabled] 时统一打印请求 / 响应（相当于拦截器）。
///
/// 通过缓冲响应字节实现日志；大文件下载场景请改用专用 Client、勿包此层。
class LoggingHttpClient extends http.BaseClient {
  LoggingHttpClient(
    this._inner, {
    this.logName = 'HTTP',
    this.enabled = true,
    this.maxLogBodyLength = 16000,
  });

  final http.Client _inner;

  /// DevTools / 控制台里按此名称过滤，例如 `EVM RPC`、`AppPrice`。
  final String logName;
  final bool enabled;

  /// 单条日志里 body 最大字符数，超出截断并附总长度。
  final int maxLogBodyLength;

  String _clip(String s) {
    if (s.length <= maxLogBodyLength) {
      return s;
    }
    return '${s.substring(0, maxLogBodyLength)}… (${s.length} chars total)';
  }

  String _bytesPreview(List<int> bytes) {
    try {
      return _clip(utf8.decode(bytes));
    } catch (_) {
      return '<binary ${bytes.length} bytes>';
    }
  }

  /// `broadcastTransaction` 的 Query `data` 为整段 base64；**禁止**打成带占位符的合成 URL，
  /// 否则 `<248 chars>` 经编码会变成 `%3C248+chars%3E`，容易被误拷进浏览器误判为真实参数。
  String _requestLineForLog(http.BaseRequest request) {
    final u = request.url;
    final path = u.path.toLowerCase();
    if (!path.contains('broadcasttransaction')) {
      return '→ ${request.method} ${u.toString()}';
    }
    if (request is http.Request && request.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(request.body);
        if (decoded is Map) {
          final ch = decoded['chain']?.toString() ?? '';
          final co = decoded['coin']?.toString() ?? '';
          final blob = decoded['data']?.toString() ?? '';
          final payloadNote = blob.isEmpty
              ? 'data=(empty in json)'
              : 'data_len=${blob.length} (json body)';
          return '→ ${request.method} ${u.scheme}://${u.authority}${u.path} '
              'dto chain=${_clip(ch)} coin=${_clip(co)} $payloadNote';
        }
      } catch (_) {}
    }
    final qp = u.queryParameters;
    final chain = qp['chain'] ?? '';
    final coin = qp['coin'] ?? '';
    final crypto = qp['crypto'] ?? '';
    final blob = qp['data'] ?? '';
    final payloadNote = blob.isEmpty
        ? 'data=(empty in query)'
        : 'data_len=${blob.length} base64 in query (full blob not repeated here)';
    return '→ ${request.method} ${u.scheme}://${u.authority}${u.path} '
        'chain=${_clip(chain)} coin=${_clip(coin)} crypto=${_clip(crypto)} $payloadNote';
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!enabled) {
      return _inner.send(request);
    }

    final head = _requestLineForLog(request);
    if (request is http.Request && request.body.isNotEmpty) {
      log('$head\n  req: ${_clip(request.body)}', name: logName);
    } else {
      log(head, name: logName);
    }

    final streamed = await _inner.send(request);
    final bytes = await streamed.stream.toBytes();
    log(
      '← ${streamed.statusCode} ${request.url.scheme}://${request.url.authority}${request.url.path}\n'
      '  resp: ${_bytesPreview(bytes)}',
      name: logName,
    );

    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      streamed.statusCode,
      contentLength: bytes.length,
      headers: streamed.headers,
      isRedirect: streamed.isRedirect,
      persistentConnection: streamed.persistentConnection,
      reasonPhrase: streamed.reasonPhrase,
      request: streamed.request,
    );
  }

  @override
  void close() {
    _inner.close();
  }
}
