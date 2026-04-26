import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/app_chain_config.dart';
import '../http/http_clients.dart';
import '../market/app_price_service.dart' show kMarketApiBase;

/// 拉取后端已启用链列表（`GET /api/app/chains`），与 [kMarketApiBase] 同源。
class ChainsService {
  ChainsService({http.Client? httpClient})
      : _httpClient = httpClient ?? _defaultClient();

  final http.Client _httpClient;

  static http.Client _defaultClient() {
    return HttpClients.create(logName: 'Chains', maxLogBodyLength: 16000);
  }

  static Uri _uri() => Uri.parse('$kMarketApiBase/api/app/chains');

  /// 失败或 `code != 0` 时返回空列表。
  Future<List<AppChainConfig>> fetchChains() async {
    try {
      final res = await _httpClient
          .get(
            _uri(),
            headers: const {'Accept': '*/*'},
          )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        return [];
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        return [];
      }
      if (decoded['code'] != 0) {
        debugPrint(
            'ChainsService: code=${decoded['code']} msg=${decoded['message']}');
        return [];
      }

      final data = decoded['data'];
      if (data is! List) {
        return [];
      }

      final out = <AppChainConfig>[];
      for (final e in data) {
        if (e is Map) {
          out.add(AppChainConfig.fromJson(Map<String, dynamic>.from(e)));
        }
      }
      return out;
    } catch (e, st) {
      debugPrint('ChainsService.fetchChains: $e\n$st');
      return [];
    }
  }
}
