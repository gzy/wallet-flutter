import '../market/app_price_service.dart' show kMarketApiBase;

/// `/api/app/wallet/*`（EVM、TRON）与 **按 `chains` 返回的 chainCode 拼路径** 的专用链（如 SOL、XRP）。
///
/// [chain] 须与 [AppChainConfig.walletApiChainQuery] 一致（优先后端 **chainCode**）。
/// 专用链的 HTTP 路径为 `/api/app/{chainCode}/…`，不再写死 `solana`/`xrp` 字面量。
abstract final class WalletApiPaths {
  WalletApiPaths._();

  /// 当前请求在路径上使用的段：`wallet` 或 **chainCode**（trim 后原样，与网关路由一致）。
  static String walletHttpNamespace(
    String chainQuery, {
    String? chainType,
  }) {
    return _pathSegment(chainQuery: chainQuery, chainType: chainType);
  }

  /// SOL / SOLANA / XRP / RIPPLE：与 wallet 不同的查询参数约定（`address`+`crypto` 等）。
  static bool _isDedicatedSolanaOrXrp({
    required String chainQuery,
    String? chainType,
  }) {
    final t = (chainType ?? '').trim().toUpperCase();
    if (t == 'SOL' || t == 'SOLANA' || t == 'XRP' || t == 'RIPPLE') {
      return true;
    }
    final q = chainQuery.trim().toUpperCase();
    if (q == 'SOL' || q == 'SOLANA' || q == 'XRP' || q == 'RIPPLE') {
      return true;
    }
    return false;
  }

  /// EVM/TRON 等聚合接口前缀为 `wallet`；专用链为 **chainCode** 本身。
  static String _pathSegment({
    required String chainQuery,
    String? chainType,
  }) {
    if (_isDedicatedSolanaOrXrp(
        chainQuery: chainQuery, chainType: chainType)) {
      final s = chainQuery.trim();
      return s.isEmpty ? 'wallet' : s;
    }
    return 'wallet';
  }

  /// 历史 / 详情是否采用专用链查询（无路径级 `chain` query，仅 `crypto` 等）。
  static bool transactionHistoryUsesCryptoQueryParam(
    String chainQuery, {
    String? chainType,
  }) {
    return _isDedicatedSolanaOrXrp(
        chainQuery: chainQuery, chainType: chainType);
  }

  static String _root(String chainQuery, {String? chainType}) =>
      '$kMarketApiBase/api/app/${_pathSegment(chainQuery: chainQuery, chainType: chainType)}';

  /// `GET …/balance`：专用链为 **`address` + `crypto`**；wallet 为 `address`+`chain`+可选 `coin`。
  static Uri balance({
    required String address,
    required String chain,
    String? coin,
    String? chainType,

    /// 专用链必填；wallet 路由忽略此字段。
    String? crypto,
  }) {
    if (_isDedicatedSolanaOrXrp(chainQuery: chain, chainType: chainType)) {
      final c = (crypto ?? '').trim();
      return Uri.parse('${_root(chain, chainType: chainType)}/balance')
          .replace(queryParameters: {
        'address': address,
        'crypto': c,
      });
    }
    final q = <String, String>{
      'address': address,
      'chain': chain,
    };
    if (coin != null && coin.isNotEmpty) {
      q['coin'] = coin;
    }
    return Uri.parse('${_root(chain, chainType: chainType)}/balance')
        .replace(queryParameters: q);
  }

  static Uri createTransaction(String chain, {String? chainType}) => Uri.parse(
        '${_root(chain, chainType: chainType)}/createTransaction',
      );

  static Uri broadcastTransaction(String chain, {String? chainType}) =>
      Uri.parse(
        '${_root(chain, chainType: chainType)}/broadcastTransaction',
      );

  /// 专用链：**`address` + `crypto`**；wallet：`address`+`chain`+可选 `coin`。
  static Uri transactionHistory({
    required String address,
    required String chain,
    String? coin,
    String? chainType,
  }) {
    if (transactionHistoryUsesCryptoQueryParam(chain, chainType: chainType)) {
      final c = (coin ?? '').trim();
      return Uri.parse(
              '${_root(chain, chainType: chainType)}/transactionHistory')
          .replace(queryParameters: {
        'address': address,
        'crypto': c,
      });
    }
    final q = <String, String>{
      'address': address,
      'chain': chain,
    };
    if (coin != null && coin.isNotEmpty) {
      q['coin'] = coin;
    }
    return Uri.parse('${_root(chain, chainType: chainType)}/transactionHistory')
        .replace(queryParameters: q);
  }

  /// 专用链：**`txHash` + `crypto`**；wallet：**`txHash` + `chain` + `crypto`**（EVM/TRON 不变）。
  static Uri transactionDetail({
    required String txHash,
    required String chain,
    required String crypto,
    String? chainType,
  }) {
    if (transactionHistoryUsesCryptoQueryParam(chain, chainType: chainType)) {
      return Uri.parse(
              '${_root(chain, chainType: chainType)}/transactionDetail')
          .replace(queryParameters: {
        'txHash': txHash,
        'crypto': crypto.trim(),
      });
    }
    return Uri.parse('${_root(chain, chainType: chainType)}/transactionDetail')
        .replace(queryParameters: {
      'txHash': txHash,
      'chain': chain,
      'crypto': crypto,
    });
  }
}
