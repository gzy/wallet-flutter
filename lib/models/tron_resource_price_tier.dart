/// 价格档位：`GET /trx/resource/price` 的 `data` 中每项。
class TronResourcePriceTier {
  const TronResourcePriceTier({
    required this.resourceValue,
    required this.energyType,
    required this.crypto,
    required this.price,
    this.transferCount,
  });

  final int resourceValue;
  final String energyType;
  final String crypto;
  final double price;

  /// 该档位大约可支持的转账笔数（后端可选返回 `count` / `transferCount`）。
  final int? transferCount;

  factory TronResourcePriceTier.fromJson(
    Map<String, dynamic> json, {
    int? resourceValueFromKey,
  }) {
    final rv = resourceValueFromKey ??
        _asInt(json['resourceValue']) ??
        0;
    return TronResourcePriceTier(
      resourceValue: rv,
      energyType: json['energyType']?.toString() ?? '',
      crypto: json['crypto']?.toString() ?? 'TRX',
      price: _asDouble(json['price']) ?? 0,
      transferCount: _asInt(json['count']) ??
          _asInt(json['transferCount']) ??
          _asInt(json['num']),
    );
  }

  static int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static double? _asDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
