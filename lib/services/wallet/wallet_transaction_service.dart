import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/chain_transaction_vo.dart';
import '../http/http_clients.dart';
import '../market/app_price_service.dart' show kMarketApiBase;

/// 钱包交易：`GET /api/app/wallet/transactionHistory`、`transactionDetail`（query 传参）；`chain` 一般为 `chainCode`（无则 `chainId`）。
class WalletTransactionService {
  WalletTransactionService({http.Client? httpClient})
      : _httpClient = httpClient ?? _defaultClient();

  final http.Client _httpClient;

  static http.Client _defaultClient() {
    return HttpClients.create(logName: 'WalletTx', maxLogBodyLength: 16000);
  }

  static Uri _detailUri({
    required String txHash,
    required String chain,
    required String crypto,
  }) {
    return Uri.parse('$kMarketApiBase/api/app/wallet/transactionDetail')
        .replace(queryParameters: {
      'txHash': txHash,
      'chain': chain,
      'crypto': crypto,
    });
  }

  static Uri _historyUri({
    required String address,
    required String chain,
    String? coin,
  }) {
    final q = <String, String>{
      'address': address,
      'chain': chain,
    };
    if (coin != null && coin.isNotEmpty) {
      q['coin'] = coin;
    }
    return Uri.parse('$kMarketApiBase/api/app/wallet/transactionHistory')
        .replace(queryParameters: q);
  }

  /// `code == 0` 时返回 `data` 列表；HTTP/解析/`code != 0` 时返回 `null`（由调用方决定是否回退 Blockscout）。
  Future<List<ChainTransactionVo>?> fetchTransactionHistory({
    required String address,
    required String chain,
    String? coin,
    String? xToken,
  }) async {
    try {
      final headers = <String, String>{'Accept': '*/*'};
      if (xToken != null && xToken.isNotEmpty) {
        headers['X-Token'] = xToken;
      }
      final res = await _httpClient
          .get(
            _historyUri(address: address, chain: chain, coin: coin),
            headers: headers,
          )
          .timeout(const Duration(seconds: 25));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (kDebugMode) {
          debugPrint('WalletTransactionService: history HTTP ${res.statusCode}');
        }
        return null;
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      if (decoded['code'] != 0) {
        if (kDebugMode) {
          debugPrint(
            'WalletTransactionService: history code=${decoded['code']} msg=${decoded['message']}',
          );
        }
        return null;
      }

      final data = decoded['data'];
      if (data is! List) {
        return [];
      }

      return data
          .whereType<Map>()
          .map((e) => ChainTransactionVo.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e, st) {
      debugPrint('WalletTransactionService.fetchTransactionHistory: $e\n$st');
      return null;
    }
  }

  /// `code == 0` 时返回 `data`；否则返回 `null`。
  Future<ChainTransactionVo?> fetchTransactionDetail({
    required String txHash,
    required String chain,
    required String crypto,
    String? xToken,
  }) async {
    try {
      final headers = <String, String>{'Accept': '*/*'};
      if (xToken != null && xToken.isNotEmpty) {
        headers['X-Token'] = xToken;
      }
      final res = await _httpClient
          .get(
            _detailUri(txHash: txHash, chain: chain, crypto: crypto),
            headers: headers,
          )
          .timeout(const Duration(seconds: 20));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (kDebugMode) {
          debugPrint('WalletTransactionService: HTTP ${res.statusCode}');
        }
        return null;
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      if (decoded['code'] != 0) {
        if (kDebugMode) {
          debugPrint(
            'WalletTransactionService: code=${decoded['code']} msg=${decoded['message']}',
          );
        }
        return null;
      }

      final data = decoded['data'];
      if (data is! Map) {
        return null;
      }
      return ChainTransactionVo.fromJson(Map<String, dynamic>.from(data));
    } catch (e, st) {
      debugPrint('WalletTransactionService.fetchTransactionDetail: $e\n$st');
      return null;
    }
  }
}
