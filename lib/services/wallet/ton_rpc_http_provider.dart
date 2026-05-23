import 'package:blockchain_utils/service/models/params.dart';
import 'package:http/http.dart' as http;
import 'package:ton_dart/ton_dart.dart';

/// [TonProvider] 使用的 HTTP RPC（TonAPI + TonCenter），与 ton_dart 示例一致。
class TonRpcHttpProvider implements TonServiceProvider {
  TonRpcHttpProvider({
    required this.tonApiUrl,
    required this.tonCenterUrl,
    this.api = TonApiType.tonApi,
    http.Client? client,
    this.defaultRequestTimeout = const Duration(seconds: 30),
  }) : client = client ?? http.Client();

  final String tonApiUrl;
  final String tonCenterUrl;
  final http.Client client;
  final Duration defaultRequestTimeout;

  @override
  final TonApiType api;

  @override
  Future<BaseServiceResponse<T>> doRequest<T>(
    TonRequestDetails params, {
    Duration? timeout,
  }) async {
    final uri = params.apiType == TonApiType.tonApi
        ? params.toUri(tonApiUrl)
        : params.toUri(tonCenterUrl);
    final headers = <String, String>{...params.headers};
    if (params.type.isPostRequest) {
      final response = await client
          .post(uri, headers: headers, body: params.body())
          .timeout(timeout ?? defaultRequestTimeout);
      return params.parseResponse(response.bodyBytes, response.statusCode);
    }
    final response = await client
        .get(uri, headers: headers)
        .timeout(timeout ?? defaultRequestTimeout);
    return params.parseResponse(response.bodyBytes, response.statusCode);
  }
}
