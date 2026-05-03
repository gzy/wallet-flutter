import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../http/http_clients.dart';
import 'chain_rules.dart';
import 'wallet_api_paths.dart';

/// 钱包转账（后端代替 RPC）：`createTransaction` + `broadcastTransaction`
///
/// - **路径**：EVM/TRON 为 `/api/app/wallet/…`；专用链（如 SOL、XRP）为
///   `/api/app/{chainCode}/…`，[chain] 须与 [AppChainConfig.walletApiChainQuery] 一致。
/// - **createTransaction**：
///   - **EVM / TRON**：`POST` + JSON 体，字段含 `gasPriceType`（**EVM** 非空为 `slow`/`medium`/`fast`，否则 `null`；TRON 为 `null`）。
///   - **SOL / XRP 等专用链**：与网关约定一致——**仅 Query**，`chain`/`coin`/`ownerAddress`/`toAddress`/`amount`/`gasPriceType`
///     （`gasPriceType` 可无值但须出现，如 `gasPriceType=`），**Body 为空**。
/// - **broadcastTransaction**：
///   - **EVM / TRON**：`POST` + JSON 体（`chain`、`coin`、`data`）。
///   - **SOL / XRP**：**仅 Query** `chain`/`coin`/`data`（已签交易 base64），**Body 为空**。
///
/// 备注：这里先不强绑定返回结构，直接把后端 `data` 原样返回给调用方，
/// 方便前端根据真实返回再做签名/广播对接。
class WalletTransferApiService {
  WalletTransferApiService({http.Client? httpClient})
      : _httpClient = httpClient ?? _defaultClient();

  final http.Client _httpClient;

  static http.Client _defaultClient() {
    return HttpClients.create(
        logName: 'WalletTransfer', maxLogBodyLength: 20000);
  }

  /// 是否采用调用方传入的 `gasPriceType` 字符串（非 EVM 时 JSON 体里仍为键 `gasPriceType: null`）。
  static bool _evmUsesGasPriceTypeParam(String chain, String? chainType) {
    final fromType = ChainRules.kindFromChainType(chainType);
    if (fromType != ChainKind.unknown) {
      return fromType == ChainKind.evm;
    }
    return ChainRules.kindFromChainQuery(chain) == ChainKind.evm;
  }

  /// SOL/XRP：`createTransaction` / `broadcastTransaction` 走 Query + 空 Body（与测试网关 curl 一致）。
  static bool _dedicatedUsesQueryPost(
    String chain,
    String? chainType,
  ) {
    final fromType = ChainRules.kindFromChainType(chainType);
    if (fromType == ChainKind.solana || fromType == ChainKind.xrp) {
      return true;
    }
    if (fromType != ChainKind.unknown) {
      return false;
    }
    final k = ChainRules.kindFromChainQuery(chain);
    return k == ChainKind.solana || k == ChainKind.xrp;
  }

  /// Query 里的 `chain`：网关示例为 `solana` / `xrp`（与路径上的 chainCode 可并存）。
  static String _dedicatedQueryChainValue(String chain, String? chainType) {
    final t = (chainType ?? '').trim().toUpperCase();
    final q = chain.trim().toUpperCase();
    if (t == 'SOLANA' || t == 'SOL' || q == 'SOL' || q == 'SOLANA') {
      return 'solana';
    }
    if (t == 'XRP' || t == 'RIPPLE' || q == 'XRP' || q == 'RIPPLE') {
      return 'xrp';
    }
    return chain.trim().toLowerCase();
  }

  static String _amountQueryString(num amount) {
    if (amount is int) {
      return amount.toString();
    }
    final d = amount.toDouble();
    if (d == d.roundToDouble()) {
      return d.toInt().toString();
    }
    return amount.toString();
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
      final base = WalletApiPaths.createTransaction(chain, chainType: chainType);
      late final http.Response res;

      if (_dedicatedUsesQueryPost(chain, chainType)) {
        final qp = <String, String>{
          'chain': _dedicatedQueryChainValue(chain, chainType),
          'coin': coin.trim(),
          'ownerAddress': ownerAddress.trim(),
          'toAddress': toAddress.trim(),
          'amount': _amountQueryString(amount),
          'gasPriceType': gasPriceType?.trim() ?? '',
        };
        res = await _httpClient
            .post(
              base.replace(queryParameters: qp),
              headers: const {
                'Accept': '*/*',
              },
              body: '',
            )
            .timeout(const Duration(seconds: 25));
      } else {
        final String? gasPriceTypeJson = _evmUsesGasPriceTypeParam(chain, chainType)
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
        res = await _httpClient
            .post(
              base,
              headers: const {
                'Accept': '*/*',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 25));
      }

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
    String? chainType,
  }) async {
    try {
      final base =
          WalletApiPaths.broadcastTransaction(chain, chainType: chainType);
      late final http.Response res;

      if (_dedicatedUsesQueryPost(chain, chainType)) {
        final qp = <String, String>{
          'chain': _dedicatedQueryChainValue(chain, chainType),
          'coin': coin.trim(),
          'data': data.trim(),
        };
        res = await _httpClient
            .post(
              base.replace(queryParameters: qp),
              headers: const {
                'Accept': '*/*',
              },
              body: '',
            )
            .timeout(const Duration(seconds: 25));
      } else {
        final payload = <String, dynamic>{
          'chain': chain,
          'coin': coin,
          'data': data,
        };
        res = await _httpClient
            .post(
              base,
              headers: const {
                'Accept': '*/*',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 25));
      }

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
