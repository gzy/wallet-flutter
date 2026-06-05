/// 与 OpenAPI `TronAccountResourceVO` 一致。
class TronAccountResourceVo {
  const TronAccountResourceVo({
    this.address,
    this.energyAvailable,
    this.energyLimit,
    this.bandwidthAvailable,
    this.bandwidthLimit,
  });

  final String? address;
  final int? energyAvailable;
  final int? energyLimit;
  final int? bandwidthAvailable;
  final int? bandwidthLimit;

  factory TronAccountResourceVo.fromJson(Map<String, dynamic> json) {
    return TronAccountResourceVo(
      address: json['address']?.toString(),
      energyAvailable: _asInt(json['energyAvailable']),
      energyLimit: _asInt(json['energyLimit']),
      bandwidthAvailable: _asInt(json['bandwidthAvailable']),
      bandwidthLimit: _asInt(json['bandwidthLimit']),
    );
  }

  static int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}
