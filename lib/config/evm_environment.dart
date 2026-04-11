import '../models/evm_network.dart';

/// 部署环境（由编译参数 [EVM_FLAVOR] 决定，**无需改源码**）。
///
/// - **testnet**：Ethereum Sepolia + Base Sepolia
/// - **mainnet**：Ethereum 主网 + Base 主网
///
/// 构建示例：
/// - `flutter run --dart-define=EVM_FLAVOR=testnet`（可省略，与默认相同）
/// - `flutter build apk --dart-define=EVM_FLAVOR=mainnet`
///
/// 亦接受 `prod` / `production` 作为正式网别名。主网 RPC 请在下方替换为自有节点。
enum EvmDeployFlavor {
  testnet,
  mainnet,
}

/// 编译期注入；未传参时默认为 `testnet`。
const String _kEvmFlavorFromEnv = String.fromEnvironment(
  'EVM_FLAVOR',
  defaultValue: 'testnet',
);

EvmDeployFlavor _parseEvmFlavor(String raw) {
  switch (raw.toLowerCase().trim()) {
    case 'mainnet':
    case 'prod':
    case 'production':
      return EvmDeployFlavor.mainnet;
    default:
      return EvmDeployFlavor.testnet;
  }
}

/// 首页 / 转账 / 收款等共用的「原生币」一行配置（与 [EvmNetworkId] 一一对应）。
class EvmNativeCoinConfig {
  const EvmNativeCoinConfig({
    required this.coinListId,
    required this.symbol,
    required this.name,
    required this.icon,
    required this.networkLabel,
    required this.networkKey,
  });

  /// 列表与持久化用 id，随环境区分，避免 test/main 缓存混淆。
  final String coinListId;
  final String symbol;
  final String name;
  final String icon;
  /// 在 UI 上展示的链名称（如 Sepolia / Ethereum）。
  final String networkLabel;
  final EvmNetworkId networkKey;
}

/// RPC、浏览器、chainId、原生币展示等统一入口。
class EvmEnvironment {
  EvmEnvironment._();

  /// 当前构建对应的环境（由 `--dart-define=EVM_FLAVOR=...` 决定）。
  static EvmDeployFlavor get flavor => _parseEvmFlavor(_kEvmFlavorFromEnv);

  static int chainId(EvmNetworkId id) {
    switch (flavor) {
      case EvmDeployFlavor.testnet:
        return switch (id) {
          EvmNetworkId.ethereum => 11155111,
          EvmNetworkId.base => 84532,
        };
      case EvmDeployFlavor.mainnet:
        return switch (id) {
          EvmNetworkId.ethereum => 1,
          EvmNetworkId.base => 8453,
        };
    }
  }

  static String rpcUrl(EvmNetworkId id) {
    switch (flavor) {
      case EvmDeployFlavor.testnet:
        return switch (id) {
          EvmNetworkId.ethereum =>
            'https://ethereum-sepolia-rpc.publicnode.com',
          EvmNetworkId.base => 'https://sepolia.base.org',
        };
      case EvmDeployFlavor.mainnet:
        return switch (id) {
          EvmNetworkId.ethereum => 'https://eth.llamarpc.com',
          EvmNetworkId.base => 'https://mainnet.base.org',
        };
    }
  }

  static String explorerTxUrl(EvmNetworkId id, String txHash) {
    final h = txHash.startsWith('0x') ? txHash : '0x$txHash';
    switch (flavor) {
      case EvmDeployFlavor.testnet:
        return switch (id) {
          EvmNetworkId.ethereum => 'https://sepolia.etherscan.io/tx/$h',
          EvmNetworkId.base => 'https://sepolia.basescan.org/tx/$h',
        };
      case EvmDeployFlavor.mainnet:
        return switch (id) {
          EvmNetworkId.ethereum => 'https://etherscan.io/tx/$h',
          EvmNetworkId.base => 'https://basescan.org/tx/$h',
        };
    }
  }

  /// 与当前 [flavor] 对应的原生 ETH 资产列表（顺序即首页/转账展示顺序）。
  static List<EvmNativeCoinConfig> get nativeCoins {
    switch (flavor) {
      case EvmDeployFlavor.testnet:
        return const [
          EvmNativeCoinConfig(
            coinListId: 'eth_sepolia',
            symbol: 'ETH',
            name: 'Ethereum',
            icon: '⚪',
            networkLabel: 'Sepolia',
            networkKey: EvmNetworkId.ethereum,
          ),
          EvmNativeCoinConfig(
            coinListId: 'eth_base_sepolia',
            symbol: 'ETH',
            name: 'Base',
            icon: '🔵',
            networkLabel: 'Base Sepolia',
            networkKey: EvmNetworkId.base,
          ),
        ];
      case EvmDeployFlavor.mainnet:
        return const [
          EvmNativeCoinConfig(
            coinListId: 'eth_mainnet',
            symbol: 'ETH',
            name: 'Ethereum',
            icon: '⚪',
            networkLabel: 'Ethereum',
            networkKey: EvmNetworkId.ethereum,
          ),
          EvmNativeCoinConfig(
            coinListId: 'eth_base',
            symbol: 'ETH',
            name: 'Base',
            icon: '🔵',
            networkLabel: 'Base',
            networkKey: EvmNetworkId.base,
          ),
        ];
    }
  }
}
