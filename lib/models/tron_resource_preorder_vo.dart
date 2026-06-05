/// 与 OpenAPI `TronResourcePreOrderVO` 一致。
class TronResourcePreOrderVo {
  const TronResourcePreOrderVo({
    required this.orderId,
    required this.transaction,
  });

  final String orderId;
  final Map<String, dynamic> transaction;

  factory TronResourcePreOrderVo.fromJson(Map<String, dynamic> json) {
    final tx = json['transaction'];
    return TronResourcePreOrderVo(
      orderId: json['orderId']?.toString() ?? '',
      transaction: tx is Map
          ? Map<String, dynamic>.from(tx)
          : <String, dynamic>{},
    );
  }
}
