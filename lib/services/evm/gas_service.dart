import 'package:web3dart/web3dart.dart';

import '../../models/evm_network.dart';
import 'evm_client.dart';

class GasService {
  /// 简单 ETH 转账的 gas 估算；失败时返回 21000
  Future<BigInt> estimateEthTransferGas({
    required EvmNetworkId network,
    required EthereumAddress from,
    required EthereumAddress to,
    required EtherAmount value,
  }) async {
    final rpc = EvmRpcClient(network);
    try {
      final gas = await rpc.raw.estimateGas(
        sender: from,
        to: to,
        value: value,
      );
      return gas;
    } catch (_) {
      return BigInt.from(21000);
    }
  }

  Future<EtherAmount?> getGasPrice(EvmNetworkId network) async {
    final rpc = EvmRpcClient(network);
    try {
      return await rpc.raw.getGasPrice();
    } catch (_) {
      return null;
    }
  }
}
