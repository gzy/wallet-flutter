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

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!enabled) {
      return _inner.send(request);
    }

    final head = '→ ${request.method} ${request.url}';
    if (request is http.Request && request.body.isNotEmpty) {
      log('$head\n  req: ${_clip(request.body)}', name: logName);
    } else {
      log(head, name: logName);
    }

    final streamed = await _inner.send(request);
    final bytes = await streamed.stream.toBytes();
    log(
      '← ${streamed.statusCode} ${request.url}\n  resp: ${_bytesPreview(bytes)}',
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
