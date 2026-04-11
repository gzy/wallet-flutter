import '../../models/evm_network.dart';

class EvmConfig {
  EvmConfig._();

  /// 公开 RPC，仅适合开发；生产请换 Infura / Alchemy 等。
  /// 主网避免使用易返回「Too many connections」纯文本、导致 JSON 解析失败的节点。
  static String rpcUrl(EvmNetworkId id) {
    switch (id) {
      case EvmNetworkId.ethereum:
        return 'https://ethereum-sepolia-rpc.publicnode.com';
      case EvmNetworkId.base:
        return 'https://mainnet.base.org';
    }
  }

  static String explorerTxUrl(EvmNetworkId id, String txHash) {
    final h = txHash.startsWith('0x') ? txHash : '0x$txHash';
    switch (id) {
      case EvmNetworkId.ethereum:
        return 'https://etherscan.io/tx/$h';
      case EvmNetworkId.base:
        return 'https://basescan.org/tx/$h';
    }
  }
}
