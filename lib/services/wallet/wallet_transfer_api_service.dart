import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../http/http_clients.dart';
import 'chain_rules.dart';
import 'wallet_api_paths.dart';

/// 钱包转账（后端代替 RPC）：`createTransaction` + `broadcastTransaction`
///
/// 统一到 **`/api/app/wallet/…`**：`POST` + JSON 体（`chain`、`coin`、…）。
/// - **createTransaction**：`chain`、`coin`、`ownerAddress`、`toAddress`、`amount`、`gasPriceType`。
///   **EVM / BTC / DOGE**：`gasPriceType` 为 `slow`/`medium`/`fast`；**其它链**（TRON、SOL、XRP 等）：JSON 中 **`gasPriceType` 为 `null`**。
/// - **broadcastTransaction**：`chain`、`coin`、`data`。
///
/// 返回：不强绑定结构，直接把后端 `data` 原样返回给调用方。
class WalletTransferApiService {
  WalletTransferApiService({http.Client? httpClient})
      : _httpClient = httpClient ?? _defaultClient();

  final http.Client _httpClient;

  static http.Client _defaultClient() {
    return HttpClients.create(
        logName: 'WalletTransfer', maxLogBodyLength: 20000);
  }

  /// 是否将 `gasPriceType`（slow/medium/fast）写入 JSON 体。
  static bool _usesGasPriceTypeParam(String chain, String? chainType) {
    final fromType = ChainRules.kindFromChainType(chainType);
    final kind = fromType != ChainKind.unknown
        ? fromType
        : ChainRules.kindFromChainQuery(chain);
  return switch (kind) {
      ChainKind.evm || ChainKind.btc || ChainKind.doge => true,
      _ => false,
    };
  }

  Future<Map<String, dynamic>?> createTransaction({
    required String chain,
    required String coin,
    required String ownerAddress,
    required String toAddress,
    required num amount,
    String? gasPriceType, // slow/medium/fast
    String? chainType,
  }) async {
    try {
      final base = WalletApiPaths.createTransactionUri();
      final String? gasPriceTypeJson = _usesGasPriceTypeParam(chain, chainType)
          ? (gasPriceType != null && gasPriceType.trim().isNotEmpty
              ? gasPriceType.trim()
              : null)
          : null;
      final payload = <String, dynamic>{
        'chain': chain,
        'coin': coin,
        'ownerAddress': ownerAddress,
        'toAddress': toAddress,
        'amount': amount,
        'gasPriceType': gasPriceTypeJson,
      };
      final res = await _httpClient
          .post(
            base,
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
      final base = WalletApiPaths.broadcastTransactionUri();
      final payload = <String, dynamic>{
        'chain': chain.trim(),
        'coin': coin.trim(),
        'data': data.trim(),
      };
      final res = await _httpClient
          .post(
            base,
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
