import 'package:web3dart/web3dart.dart';

import '../../models/evm_network.dart';
import 'evm_client.dart';

/// 去掉首尾空白与中间换行/空格，避免误粘贴导致解析异常。
String _normalizeRecipientHex(String raw) {
  return raw.trim().replaceAll(RegExp(r'[\s\n\r]+'), '');
}

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
    int? maxGas,
    EtherAmount? gasPrice,
    EtherAmount? maxFeePerGas,
    EtherAmount? maxPriorityFeePerGas,
  }) async {
    final client = EvmRpcPool.client(network);
    final cleaned = _normalizeRecipientHex(toHex);
    final to = EthereumAddress.fromHex(cleaned);
    final fromAddr = credentials.address;
    if (to.hex.toLowerCase() == fromAddr.hex.toLowerCase()) {
      throw StateError('收款地址与当前钱包相同，无法向自己转账；请粘贴对方的钱包地址。');
    }
    final wei = _etherDecimalStringToWei(amountEther);
    final is1559 = maxFeePerGas != null && maxPriorityFeePerGas != null;
    final isLegacy = gasPrice != null;
    if (is1559 && isLegacy) {
      throw ArgumentError('不能同时指定 EIP-1559 与 legacy gasPrice');
    }
    return client.sendTransaction(
      credentials,
      Transaction(
        to: to,
        value: EtherAmount.inWei(wei),
        maxGas: maxGas,
        gasPrice: is1559 ? null : gasPrice,
        maxFeePerGas: maxFeePerGas,
        maxPriorityFeePerGas: maxPriorityFeePerGas,
      ),
      chainId: network.chainId,
    );
  }
}
