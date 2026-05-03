/// 与 Expo 项目 types/crypto.ts 对应的数据模型
class CoinData {
  final String id;
  final String symbol;
  final String name;
  final String icon;
  final String? network;

  /// EVM 链 ID；非链上资产为 null
  final int? chainId;

  /// 与 `/api/app/wallet/*` 使用的 `chain` 查询参数一致（优先后端的 `chainCode`）。
  final String? walletApiChainQuery;

  /// 区块浏览器交易页前缀，如 `https://sepolia.etherscan.io/tx/`；来自 `GET /api/app/chains`。
  final String? txUrlPrefix;

  /// 区块浏览器地址页前缀，如 `https://sepolia.etherscan.io/address/`。
  final String? addressUrlPrefix;
  final double price;
  final double priceChange24h;
  final double balance;
  final double balanceUSD;

  const CoinData({
    required this.id,
    required this.symbol,
    required this.name,
    required this.icon,
    this.network,
    this.chainId,
    this.walletApiChainQuery,
    this.txUrlPrefix,
    this.addressUrlPrefix,
    required this.price,
    required this.priceChange24h,
    required this.balance,
    required this.balanceUSD,
  });

  /// 供本地 Drift 缓存「首页资产列表」快照（非链上证明，仅作离线展示）。
  Map<String, dynamic> toJson() => {
        'id': id,
        'symbol': symbol,
        'name': name,
        'icon': icon,
        'network': network,
        'chainId': chainId,
        'walletApiChainQuery': walletApiChainQuery,
        'txUrlPrefix': txUrlPrefix,
        'addressUrlPrefix': addressUrlPrefix,
        'price': price,
        'priceChange24h': priceChange24h,
        'balance': balance,
        'balanceUSD': balanceUSD,
      };

  factory CoinData.fromJson(Map<String, dynamic> j) {
    return CoinData(
      id: j['id']?.toString() ?? '',
      symbol: j['symbol']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      icon: j['icon']?.toString() ?? '',
      network: j['network']?.toString(),
      chainId: (j['chainId'] is int)
          ? j['chainId'] as int
          : int.tryParse(j['chainId']?.toString() ?? ''),
      walletApiChainQuery: j['walletApiChainQuery']?.toString(),
      txUrlPrefix: j['txUrlPrefix']?.toString(),
      addressUrlPrefix: j['addressUrlPrefix']?.toString(),
      price: (j['price'] as num?)?.toDouble() ?? 0,
      priceChange24h: (j['priceChange24h'] as num?)?.toDouble() ?? 0,
      balance: (j['balance'] as num?)?.toDouble() ?? 0,
      balanceUSD: (j['balanceUSD'] as num?)?.toDouble() ?? 0,
    );
  }
}
