import 'package:http/http.dart' as http;

import 'pinned_http_client.dart';

/// 按 host 路由到“pinned client / 默认 client”。
class RoutingHttpClient extends http.BaseClient {
  RoutingHttpClient(this._pinned);

  final PinnedHttpClient _pinned;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final host = request.url.host;
    return _pinned.clientForHost(host).send(request);
  }

  @override
  void close() {
    _pinned.close();
  }
}

