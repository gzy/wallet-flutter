import '../market/app_price_service.dart' show kMarketApiBase;

/// 钱包 HTTP 路径前缀：**`/api/app/wallet/*`**
///
/// [chain] 须与 [AppChainConfig.walletApiChainQuery] 一致（优先后端 **chainCode**），
/// 作为查询参数或 JSON 字段传给网关，**不再**拼入路径段（已无 `/api/app/solana/…` 等专用前缀）。
abstract final class WalletApiPaths {
  WalletApiPaths._();

  static const String _walletRoot = '$kMarketApiBase/api/app/wallet';

  /// `POST …/balances/batch`：请求体 `BatchWalletBalanceDTO`（`items[]`）。
  static Uri balancesBatchUri() =>
      Uri.parse('$_walletRoot/balances/batch');

  /// `GET …/balance`：`address` + `chain` + 可选 `coin`。
  static Uri balance({
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
    return Uri.parse('$_walletRoot/balance').replace(queryParameters: q);
  }

  /// 固定 `POST …/wallet/createTransaction`；`chain` / `chainType` 在 JSON 体中传递。
  static Uri createTransactionUri() =>
      Uri.parse('$_walletRoot/createTransaction');

  /// 固定 `POST …/wallet/broadcastTransaction`；`chain` / `chainType` 在 JSON 体中传递。
  static Uri broadcastTransactionUri() =>
      Uri.parse('$_walletRoot/broadcastTransaction');

  /// `GET …/transactionHistory`：`address` + `chain` + 可选 `coin`。
  static Uri transactionHistory({
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
    return Uri.parse('$_walletRoot/transactionHistory')
        .replace(queryParameters: q);
  }

  /// `GET …/transactionDetail`：`txHash` + `chain` + `crypto`。
  static Uri transactionDetail({
    required String txHash,
    required String chain,
    required String crypto,
  }) {
    return Uri.parse('$_walletRoot/transactionDetail').replace(
      queryParameters: {
        'txHash': txHash,
        'chain': chain,
        'crypto': crypto.trim(),
      },
    );
  }
}
