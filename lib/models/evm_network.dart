import '../config/evm_environment.dart';

/// 应用内支持的 EVM 网络（逻辑链：Ethereum 系 + Base 系；具体主/测由 [EvmEnvironment] 决定）。
enum EvmNetworkId {
  ethereum,
  base,
}

extension EvmNetworkIdX on EvmNetworkId {
  int get chainId => EvmEnvironment.chainId(this);

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
