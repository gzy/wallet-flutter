import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../http/http_clients.dart';
import '../market/app_price_service.dart' show kMarketApiBase;

/// 钱包转账（后端代替 RPC）：`createTransaction` + `broadcastTransaction`
///
/// 备注：这里先不强绑定返回结构，直接把后端 `data` 原样返回给调用方，
/// 方便前端根据真实返回再做签名/广播对接。
class WalletTransferApiService {
  WalletTransferApiService({http.Client? httpClient})
      : _httpClient = httpClient ?? _defaultClient();

  final http.Client _httpClient;

  static http.Client _defaultClient() {
    return HttpClients.create(logName: 'WalletTransfer', maxLogBodyLength: 20000);
  }

  static Uri _createUri() =>
      Uri.parse('$kMarketApiBase/api/app/wallet/createTransaction');

  static Uri _broadcastUri() =>
      Uri.parse('$kMarketApiBase/api/app/wallet/broadcastTransaction');

  Future<Map<String, dynamic>?> createTransaction({
    required String chain,
    required String coin,
    required String ownerAddress,
    required String toAddress,
    required num amount,
    String? gasPriceType, // slow/medium/fast
  }) async {
    try {
      final payload = <String, dynamic>{
        'chain': chain,
        'coin': coin,
        'ownerAddress': ownerAddress,
        'toAddress': toAddress,
        'amount': amount,
        if (gasPriceType != null && gasPriceType.isNotEmpty)
          'gasPriceType': gasPriceType,
      };
      final res = await _httpClient
          .post(
            _createUri(),
            headers: const {
              'Accept': '*/*',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 25));

      final decoded = jsonDecode(res.body);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } catch (e, st) {
      debugPrint('WalletTransferApiService.createTransaction: $e\n$st');
      return null;
    }
  }

  Future<Map<String, dynamic>?> broadcastTransaction({
    required String chain,
    required String coin,
    required String data,
  }) async {
    try {
      final payload = <String, dynamic>{
        'chain': chain,
        'coin': coin,
        'data': data,
      };
      final res = await _httpClient
          .post(
            _broadcastUri(),
            headers: const {
              'Accept': '*/*',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 25));

      final decoded = jsonDecode(res.body);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } catch (e, st) {
      debugPrint('WalletTransferApiService.broadcastTransaction: $e\n$st');
      return null;
    }
  }
}

