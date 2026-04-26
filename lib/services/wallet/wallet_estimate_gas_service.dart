import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../http/http_clients.dart';
import '../market/app_price_service.dart' show kMarketApiBase;

/// 后端 `POST /api/app/wallet/estimateGas`：返回 `gasLimit` 等，用于不依赖链上 RPC 估算手续费。
class WalletEstimateGasService {
  WalletEstimateGasService({http.Client? httpClient})
      : _httpClient = httpClient ?? _defaultClient();

  final http.Client _httpClient;

  static http.Client _defaultClient() {
    return HttpClients.create(logName: 'WalletEstimateGas', maxLogBodyLength: 20000);
  }

  static Uri _uri() => Uri.parse('$kMarketApiBase/api/app/wallet/estimateGas');

  /// `code==0` 时返回 [data]（一般为 Map，含 `gasLimit`），否则 `null`。
  Future<Object?> estimateGas({
    required String chain,
    required String coin,
    required String ownerAddress,
    required String toAddress,
    required num amount,
  }) async {
    try {
      final payload = <String, dynamic>{
        'chain': chain,
        'coin': coin,
        'ownerAddress': ownerAddress,
        'toAddress': toAddress,
        'amount': amount,
      };
      final res = await _httpClient
          .post(
            _uri(),
            headers: const {
              'Accept': '*/*',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 25));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (kDebugMode) {
          debugPrint('WalletEstimateGasService: HTTP ${res.statusCode}');
        }
        return null;
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic> || decoded['code'] != 0) {
        if (kDebugMode) {
          debugPrint(
            'WalletEstimateGasService: code=${decoded is Map ? decoded['code'] : 'n/a'}',
          );
        }
        return null;
      }
      return decoded['data'];
    } catch (e, st) {
      debugPrint('WalletEstimateGasService.estimateGas: $e\n$st');
      return null;
    }
  }

  static int? parseGasLimit(Object? data) {
    if (data == null) return null;
    if (data is int) {
      return data > 0 ? data : null;
    }
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      final v = m['gasLimit'] ?? m['gas'] ?? m['gas_limit'];
      if (v is int) return v > 0 ? v : null;
      if (v is num) {
        final i = v.round();
        return i > 0 ? i : null;
      }
      if (v is String) {
        final p = int.tryParse(v);
        if (p != null && p > 0) return p;
      }
    }
    return null;
  }
}
