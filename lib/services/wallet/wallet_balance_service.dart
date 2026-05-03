import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../http/http_clients.dart';
import 'wallet_api_paths.dart';

/// 与 OpenAPI `GET /api/app/wallet/balance`（`WalletBalanceVO`）一致的单条余额。
class WalletBalanceEntry {
  const WalletBalanceEntry({
    required this.balance,
    this.chain,
    this.crypto,
    this.protocol,
  });

  final double balance;
  final String? chain;
  final String? crypto;
  final String? protocol;

  factory WalletBalanceEntry.fromJson(Map<String, dynamic> json) {
    return WalletBalanceEntry(
      balance: (json['balance'] as num?)?.toDouble() ?? 0,
      chain: json['chain']?.toString(),
      crypto: json['crypto']?.toString(),
      protocol: json['protocol']?.toString(),
    );
  }
}

/// 后端聚合余额（与链上 RPC 二选一由 [WalletController] 决定）。
///
/// OpenAPI：`…/solana/balance`、`…/xrp/balance` 为 **`address`+`crypto`**；`…/wallet/balance` 为 `address`+`chain`（及可选 `coin`）。
class WalletBalanceService {
  WalletBalanceService({http.Client? httpClient})
      : _httpClient = httpClient ?? _defaultClient();

  final http.Client _httpClient;

  static http.Client _defaultClient() {
    return HttpClients.create(
        logName: 'WalletBalance', maxLogBodyLength: 12000);
  }

  /// 成功且 `code == 0` 时返回 `data` 列表（可能为空）；HTTP/解析/`code != 0` 时返回 `null`。
  Future<List<WalletBalanceEntry>?> fetchBalances({
    required String address,
    required String chain,
    String? coin,

    /// 与 [/api/app/chains] `chainType` 一致时可纠正 solana/xrp 前缀（避免仅 `chainQuery` 非 XRP 字面量时走错 wallet 路由）。
    String? chainType,

    /// solana/xrp 余额必填，与 `cryptos[].crypto` 或当前币种符号一致。
    String? crypto,
  }) async {
    try {
      final res = await _httpClient.get(
        WalletApiPaths.balance(
          address: address,
          chain: chain,
          coin: coin,
          chainType: chainType,
          crypto: crypto,
        ),
        headers: const {'Accept': '*/*'},
      ).timeout(const Duration(seconds: 20));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (kDebugMode) {
          debugPrint('WalletBalanceService: HTTP ${res.statusCode}');
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
            'WalletBalanceService: code=${decoded['code']} msg=${decoded['message']}',
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
          .map((e) => WalletBalanceEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e, st) {
      debugPrint('WalletBalanceService.fetchBalances: $e\n$st');
      return null;
    }
  }
}
