/// 预购请求体 `TronResourcePreOrderDTO`。
class TronResourcePreOrderDto {
  const TronResourcePreOrderDto({
    required this.energyType,
    required this.resourceValue,
    required this.payerAddress,
    required this.toAddress,
    required this.count,
    this.crypto = 'TRX',
  });

  final String energyType;
  final int resourceValue;
  final String payerAddress;
  final String toAddress;

  /// 必传：笔数套餐为购买笔数（≥5）；快速租用固定为 1。
  final int count;
  final String crypto;

  Map<String, dynamic> toJson() => {
        'energyType': energyType,
        'resourceValue': resourceValue,
        'crypto': crypto,
        'payerAddress': payerAddress,
        'toAddress': toAddress,
        'count': count,
      };
}
