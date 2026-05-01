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

  /// 链 ID（字符串，如 `11155111`），多见于 EVM；Solana 等可无此字段而为空字符串。
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

  /// 钱包接口 `chain` 查询参数：后端约定优先 [chainCode]，缺失或为空时回退 [chainId]。
  String get walletApiChainQuery {
    final c = chainCode?.trim();
    if (c != null && c.isNotEmpty) {
      return c;
    }
    return chainId;
  }

  Map<String, dynamic> toJson() => {
        'chainId': chainId,
        'chainType': chainType,
        'chainName': chainName,
        'symbol': symbol,
        'chainCode': chainCode,
        'explorerUrl': explorerUrl,
        'addressUrlPrefix': addressUrlPrefix,
        'txUrlPrefix': txUrlPrefix,
        'status': status,
        'version': version,
        'cryptos': cryptos.map((c) => c.toJson()).toList(),
      };
}

extension AppChainConfigIdentifiers on AppChainConfig {
  /// 列表去重用：有数值/字符串 [chainId] 时用链 Id；否则用钱包接口 `chain` 参数（如 SOL）。
  String get backendStableSegment {
    final id = chainId.trim();
    if (id.isNotEmpty) {
      return id;
    }
    return walletApiChainQuery.trim();
  }

  /// [CoinData.id]：带 chainId 的链沿用 `evm_` 前缀以兼容历史；无 chainId 时用 `chain_` + 查询参数。
  String coinPrimaryId(String symbolUpper) {
    final sym = symbolUpper.toUpperCase();
    final id = chainId.trim();
    if (id.isNotEmpty) {
      return 'evm_${id}_$sym';
    }
    final q = walletApiChainQuery.trim();
    return 'chain_${q}_$sym';
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

  Map<String, dynamic> toJson() => {
        'crypto': crypto,
        'cryptoName': cryptoName,
        'protocol': protocol,
        'contractAddress': contractAddress,
        'decimals': decimals,
        'isNative': isNative,
        'logoUrl': logoUrl,
      };
}
