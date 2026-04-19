/// 与 OpenAPI `ChainTransactionVO` / `POST /api/app/wallet/transactionDetail` 的 `data` 一致。
class ChainTransactionVo {
  const ChainTransactionVo({
    this.crypto,
    this.chain,
    this.chainName,
    this.txHash,
    this.fromAddress,
    this.toAddress,
    this.quantity,
    this.blockNumber,
    this.status,
    this.fundDirection,
    this.contractAddress,
    this.protocol,
    this.transactionTime,
    this.includeDetail,
    this.transactionFee,
    this.feeCrypto,
    this.txLink,
    this.addressLinkPrefix,
  });

  final String? crypto;
  final String? chain;
  final String? chainName;
  final String? txHash;
  final String? fromAddress;
  final String? toAddress;
  final double? quantity;
  final String? blockNumber;
  final int? status;
  final String? fundDirection;
  final String? contractAddress;
  final String? protocol;
  final DateTime? transactionTime;
  final String? includeDetail;
  final double? transactionFee;
  final String? feeCrypto;
  final String? txLink;
  final String? addressLinkPrefix;

  factory ChainTransactionVo.fromJson(Map<String, dynamic> json) {
    DateTime? time;
    final raw = json['transactionTime'];
    if (raw != null) {
      time = DateTime.tryParse(raw.toString());
    }
    return ChainTransactionVo(
      crypto: json['crypto']?.toString(),
      chain: json['chain']?.toString(),
      chainName: json['chainName']?.toString(),
      txHash: json['txHash']?.toString(),
      fromAddress: json['fromAddress']?.toString(),
      toAddress: json['toAddress']?.toString(),
      quantity: (json['quantity'] as num?)?.toDouble(),
      blockNumber: json['blockNumber']?.toString(),
      status: _asInt(json['status']),
      fundDirection: json['fundDirection']?.toString(),
      contractAddress: json['contractAddress']?.toString(),
      protocol: json['protocol']?.toString(),
      transactionTime: time,
      includeDetail: json['includeDetail']?.toString(),
      transactionFee: (json['transactionFee'] as num?)?.toDouble(),
      feeCrypto: json['feeCrypto']?.toString(),
      txLink: json['txLink']?.toString(),
      addressLinkPrefix: json['addressLinkPrefix']?.toString(),
    );
  }
}

int? _asInt(Object? v) {
  if (v == null) {
    return null;
  }
  if (v is int) {
    return v;
  }
  return int.tryParse(v.toString());
}
