int? _asInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  return int.tryParse(v.toString());
}

/// 与后端 `GET /api/app/chains` 返回的 `data[]` 项对应。
class AppChainConfig {
  const AppChainConfig({
    required this.chainId,
    required this.chainType,
    required this.chainName,
    required this.symbol,
    this.chainCode,
    this.explorerUrl,
    this.addressUrlPrefix,
    this.txUrlPrefix,
    this.status,
    this.version,
    this.cryptos = const [],
  });

  /// 链标识（字符串），与余额等接口的 `chain` 查询参数对齐时多用此字段。
  final String chainId;
  final String chainType;
  final String chainName;
  final String symbol;
  final String? chainCode;
  final String? explorerUrl;
  final String? addressUrlPrefix;
  final String? txUrlPrefix;
  final int? status;
  final int? version;
  final List<AppChainCrypto> cryptos;

  factory AppChainConfig.fromJson(Map<String, dynamic> json) {
    final rawList = json['cryptos'];
    final list = <AppChainCrypto>[];
    if (rawList is List) {
      for (final e in rawList) {
        if (e is Map) {
          list.add(AppChainCrypto.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return AppChainConfig(
      chainId: json['chainId']?.toString() ?? '',
      chainType: json['chainType']?.toString() ?? '',
      chainName: json['chainName']?.toString() ?? '',
      symbol: json['symbol']?.toString() ?? '',
      chainCode: json['chainCode']?.toString(),
      explorerUrl: json['explorerUrl']?.toString(),
      addressUrlPrefix: json['addressUrlPrefix']?.toString(),
      txUrlPrefix: json['txUrlPrefix']?.toString(),
      status: _asInt(json['status']),
      version: _asInt(json['version']),
      cryptos: list,
    );
  }

}

class AppChainCrypto {
  const AppChainCrypto({
    required this.crypto,
    this.cryptoName,
    this.protocol,
    this.contractAddress,
    this.decimals,
    this.isNative,
    this.logoUrl,
  });

  final String crypto;
  final String? cryptoName;
  final String? protocol;
  final String? contractAddress;
  final int? decimals;
  final int? isNative;
  final String? logoUrl;

  factory AppChainCrypto.fromJson(Map<String, dynamic> json) {
    return AppChainCrypto(
      crypto: json['crypto']?.toString() ?? '',
      cryptoName: json['cryptoName']?.toString(),
      protocol: json['protocol']?.toString(),
      contractAddress: json['contractAddress']?.toString(),
      decimals: _asInt(json['decimals']),
      isNative: _asInt(json['isNative']),
      logoUrl: json['logoUrl']?.toString(),
    );
  }
}
