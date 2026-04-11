/// 应用内支持的 EVM 网络（Phase 1：Ethereum 主网 + Base 主网）
enum EvmNetworkId {
  ethereum,
  base,
}

extension EvmNetworkIdX on EvmNetworkId {
  int get chainId {
    switch (this) {
      case EvmNetworkId.ethereum:
        return 11155111;
      case EvmNetworkId.base:
        return 8453;
    }
  }

  String get displayName {
    switch (this) {
      case EvmNetworkId.ethereum:
        return 'Ethereum';
      case EvmNetworkId.base:
        return 'Base';
    }
  }

  String get shortLabel {
    switch (this) {
      case EvmNetworkId.ethereum:
        return 'Ethereum';
      case EvmNetworkId.base:
        return 'Base';
    }
  }
}
