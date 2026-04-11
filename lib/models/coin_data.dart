/// 与 Expo 项目 types/crypto.ts 对应的数据模型
class CoinData {
  final String id;
  final String symbol;
  final String name;
  final String icon;
  final String? network;
  /// EVM 链 ID（随 [EvmEnvironment] 主/测变化，如 1、11155111、8453、84532）；非链上资产为 null
  final int? chainId;
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
    required this.price,
    required this.priceChange24h,
    required this.balance,
    required this.balanceUSD,
  });
}
