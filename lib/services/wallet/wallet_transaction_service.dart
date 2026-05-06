import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/chain_transaction_vo.dart';
import '../http/http_clients.dart';
import 'wallet_api_paths.dart';

/// 钱包交易：`GET …/transactionHistory`、`transactionDetail`；SOL/XRP 为 **`address`+`crypto`** / **`txHash`+`crypto`**；wallet 仍带 `chain`（EVM/TRON 不变）。
class WalletTransactionService {
  WalletTransactionService({http.Client? httpClient})
      : _httpClient = httpClient ?? _defaultClient();

  final http.Client _httpClient;

  static http.Client _defaultClient() {
    return HttpClients.create(logName: 'WalletTx', maxLogBodyLength: 16000);
  }

  /// 网关 `txHash` 通常为连续 hex/base58；若列表里误带空格/换行，先去掉以免 URL 中出现 `%20` 等编码。
  static String normalizeTxHashForApi(String txHash) =>
      txHash.replaceAll(RegExp(r'\s+'), '').trim();

  /// `code == 0` 时返回 `data` 列表；HTTP/解析/`code != 0` 时返回 `null`（由调用方决定是否回退 Blockscout）。
  Future<List<ChainTransactionVo>?> fetchTransactionHistory({
    required String address,
    required String chain,
    String? coin,
    String? chainType,
    String? xToken,
  }) async {
    try {
      final headers = <String, String>{'Accept': '*/*'};
      if (xToken != null && xToken.isNotEmpty) {
        headers['X-Token'] = xToken;
      }
      final res = await _httpClient
          .get(
            WalletApiPaths.transactionHistory(
              address: address,
              chain: chain,
              coin: coin,
              chainType: chainType,
            ),
            headers: headers,
          )
          .timeout(const Duration(seconds: 25));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (kDebugMode) {
          debugPrint(
              'WalletTransactionService: history HTTP ${res.statusCode}');
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
    String? chainType,
    String? xToken,
  }) async {
    try {
      final headers = <String, String>{'Accept': '*/*'};
      if (xToken != null && xToken.isNotEmpty) {
        headers['X-Token'] = xToken;
      }
      final h = normalizeTxHashForApi(txHash);
      if (h.isEmpty) {
        return null;
      }
      final res = await _httpClient
          .get(
            WalletApiPaths.transactionDetail(
              txHash: h,
              chain: chain,
              crypto: crypto,
              chainType: chainType,
            ),
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
