/// 与 OpenAPI `ChainTransactionVO`、钱包 `transactionHistory` 列表项及 `transactionDetail` 的 `data` 字段一致。
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

  /// 列表接口里 [includeDetail] 为 `Y` 等真值时，字段已够展示详情，无需再调 `transactionDetail`。
  bool get walletHistoryRowIncludesDetail {
    final v = includeDetail?.trim().toUpperCase();
    return v == 'Y' || v == 'YES' || v == 'TRUE' || v == '1';
  }

  factory ChainTransactionVo.fromJson(Map<String, dynamic> json) {
    DateTime? time;
    final raw = json['transactionTime'];
    if (raw != null) {
      time = _parseTransactionTime(raw.toString());
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

  Map<String, dynamic> toJson() => {
        'crypto': crypto,
        'chain': chain,
        'chainName': chainName,
        'txHash': txHash,
        'fromAddress': fromAddress,
        'toAddress': toAddress,
        'quantity': quantity,
        'blockNumber': blockNumber,
        'status': status,
        'fundDirection': fundDirection,
        'contractAddress': contractAddress,
        'protocol': protocol,
        'transactionTime': transactionTime?.toIso8601String(),
        'includeDetail': includeDetail,
        'transactionFee': transactionFee,
        'feeCrypto': feeCrypto,
        'txLink': txLink,
        'addressLinkPrefix': addressLinkPrefix,
      };
}

/// 支持 ISO8601 及常见后端格式 `yyyy-MM-dd HH:mm:ss`（无时区时按本地日历解析）。
DateTime? _parseTransactionTime(String raw) {
  final s = raw.trim();
  if (s.isEmpty) {
    return null;
  }
  final iso = DateTime.tryParse(s);
  if (iso != null) {
    return iso;
  }
  final m = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?',
  ).firstMatch(s);
  if (m == null) {
    return null;
  }
  final sec = m[6] != null ? int.parse(m[6]!) : 0;
  return DateTime(
    int.parse(m[1]!),
    int.parse(m[2]!),
    int.parse(m[3]!),
    int.parse(m[4]!),
    int.parse(m[5]!),
    sec,
  );
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
