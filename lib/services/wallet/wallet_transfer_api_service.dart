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
///   - **EVM / TRON / XRP**：`POST` + JSON 体（`chain`、`coin`、`ownerAddress`、`toAddress`、`amount`、`gasPriceType`；
///     **EVM** 的 `gasPriceType` 非空为 `slow`/`medium`/`fast`，否则 `null`；TRON / XRP 为 `null`）。
///   - **Solana**：**仅 Query** + 空 Body（`chain`/`coin`/…/`gasPriceType=` 等，与旧网关一致）。
/// - **broadcastTransaction**：
///   - **EVM / TRON / XRP**：`POST` + JSON 体（`chain`、`coin`、`data`）。
///     与 OpenAPI `/api/app/xrp/broadcastTransaction` 一致；**不可用** Query + 空 Body。
///   - **Solana**：OpenAPI 为 Query `dto`（见实现）；仍为 **POST** + Query，**Body 为空**。
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

  /// 仅 **Solana**：`broadcastTransaction` 为 **Query** + 空 Body（与网关旧约定一致）。
  /// **XRP** 与 OpenAPI 一致，走下方 **JSON Body** 分支（`BroadcastTransactionDTO`）。
  static bool _dedicatedBroadcastUsesQueryPost(
    String chain,
    String? chainType,
  ) {
    final fromType = ChainRules.kindFromChainType(chainType);
    if (fromType == ChainKind.solana) {
      return true;
    }
    if (fromType != ChainKind.unknown) {
      return false;
    }
    return ChainRules.kindFromChainQuery(chain) == ChainKind.solana;
  }

  /// 仅 **Solana** 的 `createTransaction` 走 Query + 空 Body；**XRP** 与 EVM/TRON 一样用 JSON Body。
  static bool _solanaCreateUsesQueryPost(
    String chain,
    String? chainType,
  ) {
    final fromType = ChainRules.kindFromChainType(chainType);
    if (fromType == ChainKind.solana) {
      return true;
    }
    if (fromType != ChainKind.unknown) {
      return false;
    }
    return ChainRules.kindFromChainQuery(chain) == ChainKind.solana;
  }

  /// **`BroadcastTransactionDTO.chain`**：专用链必须用网关注册码（`xrp` / `solana`），
  /// 传 `XRP` 等会触发服务端 `Invalid Blockchain Code`（与 Query 广播中的 `chain` 一致）。
  static String _broadcastDtoChain(String chain, String? chainType) {
    final fromType = ChainRules.kindFromChainType(chainType);
    if (fromType == ChainKind.solana || fromType == ChainKind.xrp) {
      return _dedicatedQueryChainValue(chain, chainType);
    }
    if (fromType != ChainKind.unknown) {
      return chain.trim();
    }
    final k = ChainRules.kindFromChainQuery(chain);
    if (k == ChainKind.solana || k == ChainKind.xrp) {
      return _dedicatedQueryChainValue(chain, chainType);
    }
    return chain.trim();
  }

  /// **`BroadcastTransactionDTO.coin`**：专用链与网关 history/balance 常用小写 `xrp`/`sol`。
  static String _broadcastDtoCoin(String chain, String? chainType, String coin) {
    final c = coin.trim();
    final fromType = ChainRules.kindFromChainType(chainType);
    if (fromType == ChainKind.solana ||
        fromType == ChainKind.xrp ||
        ChainRules.kindFromChainQuery(chain) == ChainKind.solana ||
        ChainRules.kindFromChainQuery(chain) == ChainKind.xrp) {
      return c.toLowerCase();
    }
    return c;
  }

  /// Query 里的 `chain`：网关示例为 `solana` / `xrp`（与路径上的 chainCode 可并存）。
  static String _dedicatedQueryChainValue(String chain, String? chainType) {
    final t = (chainType ?? '').trim().toUpperCase();
    final q = chain.trim().toUpperCase();
    if (t == 'SOLANA' || t == 'SOL' || q == 'SOL' || q == 'SOLANA') {
      return 'solana';
    }
    if (t == 'XRP' ||
        t == 'RIPPLE' ||
        t == 'XRPL' ||
        q == 'XRP' ||
        q == 'RIPPLE') {
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
      final base =
          WalletApiPaths.createTransaction(chain, chainType: chainType);
      late final http.Response res;

      if (_solanaCreateUsesQueryPost(chain, chainType)) {
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
        final String? gasPriceTypeJson =
            _evmUsesGasPriceTypeParam(chain, chainType)
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

      if (_dedicatedBroadcastUsesQueryPost(chain, chainType)) {
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
          'chain': _broadcastDtoChain(chain, chainType),
          'coin': _broadcastDtoCoin(chain, chainType, coin),
          'data': data.trim(),
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
