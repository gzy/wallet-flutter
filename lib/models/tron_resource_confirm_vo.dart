/// 与 OpenAPI `TronResourceConfirmVO` 一致。
class TronResourceConfirmVo {
  const TronResourceConfirmVo({
    this.orderId,
    this.toAddress,
    this.txHash,
    this.totalAmount,
    this.crypto,
  });

  final String? orderId;
  final String? toAddress;
  final String? txHash;
  final double? totalAmount;
  final String? crypto;

  factory TronResourceConfirmVo.fromJson(Map<String, dynamic> json) {
    return TronResourceConfirmVo(
      orderId: json['orderId']?.toString(),
      toAddress: json['toAddress']?.toString(),
      txHash: json['txHash']?.toString(),
      totalAmount: _asDouble(json['totalAmount']),
      crypto: json['crypto']?.toString(),
    );
  }

  static double? _asDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
