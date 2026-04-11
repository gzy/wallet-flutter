import 'package:web3dart/web3dart.dart';

import '../../models/evm_network.dart';
import 'evm_client.dart';

class TokenService {
  /// 查询原生 ETH 余额（wei → ether double）
  Future<double> getEthBalanceEther(EvmNetworkId network, EthereumAddress address) async {
    final rpc = EvmRpcClient(network);
    final b = await rpc.getBalance(address);
    return b.getValueInUnit(EtherUnit.ether).toDouble();
  }
}
