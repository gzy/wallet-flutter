import 'package:web3dart/web3dart.dart';

import '../../models/evm_network.dart';
import 'evm_client.dart';

BigInt _etherDecimalStringToWei(String amount) {
  final s = amount.trim();
  if (s.isEmpty) {
    throw const FormatException('empty amount');
  }
  if (s.startsWith('-')) {
    throw const FormatException('negative amount');
  }
  final parts = s.split('.');
  if (parts.length > 2) {
    throw const FormatException('invalid amount');
  }
  var whole = parts[0].isEmpty ? '0' : parts[0];
  if (whole.isEmpty) {
    whole = '0';
  }
  var frac = parts.length > 1 ? parts[1] : '';
  if (frac.length > 18) {
    frac = frac.substring(0, 18);
  }
  frac = frac.padRight(18, '0');
  return BigInt.parse(whole) * BigInt.from(10).pow(18) + BigInt.parse(frac);
}

class SendService {
  /// 广播原生 ETH 转账，返回 tx hash。[amountEther] 为十进制 ETH 字符串（如 `1`、`0.1`）。
  Future<String> sendEth({
    required EvmNetworkId network,
    required EthPrivateKey credentials,
    required String toHex,
    required String amountEther,
  }) async {
    final client = EvmRpcPool.client(network);
    final to = EthereumAddress.fromHex(toHex.trim());
    final wei = _etherDecimalStringToWei(amountEther);
    return client.sendTransaction(
      credentials,
      Transaction(
        to: to,
        value: EtherAmount.inWei(wei),
      ),
      chainId: network.chainId,
    );
  }
}
