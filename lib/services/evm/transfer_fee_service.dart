import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

import '../../models/evm_network.dart';
import 'evm_client.dart';

/// 原生 ETH 转账的 Gas 报价（EIP-1559 或 legacy），供确认页展示与 [SendService.sendEth] 使用。
class NativeTransferFeeQuote {
  NativeTransferFeeQuote({
    required this.gasLimit,
    required this.isEip1559,
    required this.nextBaseFeeWei,
    required this.tipLowWei,
    required this.tipMedWei,
    required this.tipHighWei,
    this.legacyGasPriceWei,
  });

  /// 含少量缓冲的 gas limit（wei 计费时用）。
  final int gasLimit;

  /// 为 true 时使用 [tip*Wei] + [nextBaseFeeWei] 计算 maxFee；否则用 [legacyGasPriceWei]。
  final bool isEip1559;

  /// 下一区块基础费（wei / gas），来自 fee history 末项。
  final BigInt nextBaseFeeWei;

  final BigInt tipLowWei;
  final BigInt tipMedWei;
  final BigInt tipHighWei;

  /// Legacy 模式下的 gas price（wei / gas）。
  final BigInt? legacyGasPriceWei;

  /// 与 web3dart 默认一致：`maxFee = 2 * base + priority`，可覆盖 base 短时上涨。
  static BigInt maxFeePerGasWei(BigInt base, BigInt priority) {
    return base * BigInt.from(2) + priority;
  }

  BigInt _tipForLevel(String level, BigInt customPriorityWei) {
    switch (level) {
      case '低':
        return tipLowWei;
      case '中':
        return tipMedWei;
      case '高':
        return tipHighWei;
      case '自定义':
        return customPriorityWei;
      default:
        return tipMedWei;
    }
  }

  /// 用于发送交易：根据档位与自定义 tip（仅自定义档使用 [customPriorityWei]，其余忽略）。
  ({
    int maxGas,
    EtherAmount? gasPrice,
    EtherAmount? maxFeePerGas,
    EtherAmount? maxPriorityFeePerGas,
  }) transactionParams({
    required String gasLevel,
    required BigInt customPriorityWei,
  }) {
    if (isEip1559) {
      final tip = _tipForLevel(gasLevel, customPriorityWei);
      final tipAmt = EtherAmount.inWei(tip);
      final maxFee = EtherAmount.inWei(maxFeePerGasWei(nextBaseFeeWei, tip));
      return (
        maxGas: gasLimit,
        gasPrice: null,
        maxFeePerGas: maxFee,
        maxPriorityFeePerGas: tipAmt,
      );
    }
    final base = legacyGasPriceWei ?? BigInt.zero;
    final mult = switch (gasLevel) {
      '低' => BigInt.from(90),
      '中' => BigInt.from(100),
      '高' => BigInt.from(115),
      '自定义' => BigInt.from(100),
      _ => BigInt.from(100),
    };
    var price = base * mult ~/ BigInt.from(100);
    if (gasLevel == '自定义') {
      price = customPriorityWei;
    }
    if (price <= BigInt.zero) {
      price = BigInt.from(1000000000);
    }
    return (
      maxGas: gasLimit,
      gasPrice: EtherAmount.inWei(price),
      maxFeePerGas: null,
      maxPriorityFeePerGas: null,
    );
  }

  /// 展示用：某档「最多约」支付 ETH 量 = gasLimit * maxFeePerGas。
  double approxMaxEthForLevel(String level, BigInt customPriorityWei) {
    final p = transactionParams(gasLevel: level, customPriorityWei: customPriorityWei);
    final weiPerGas = p.maxFeePerGas?.getInWei ?? p.gasPrice!.getInWei;
    final totalWei = BigInt.from(gasLimit) * weiPerGas;
    return EtherAmount.inWei(totalWei).getValueInUnit(EtherUnit.ether);
  }

  String gweiLabelForLevel(String level, BigInt customPriorityWei) {
    if (!isEip1559) {
      final p = transactionParams(gasLevel: level, customPriorityWei: customPriorityWei);
      final g = p.gasPrice!.getValueInUnit(EtherUnit.gwei);
      return '${g.toStringAsFixed(g < 0.01 ? 6 : 4)} Gwei';
    }
    final tip = _tipForLevel(level, customPriorityWei);
    final g = EtherAmount.inWei(tip).getValueInUnit(EtherUnit.gwei);
    return '${g.toStringAsFixed(g < 0.01 ? 6 : 4)} Gwei';
  }
}

BigInt _medianBigInt(List<BigInt> values) {
  if (values.isEmpty) {
    return BigInt.zero;
  }
  final s = [...values]..sort();
  return s[s.length ~/ 2];
}

List<BigInt> _tipsAtPercentile(List<dynamic> rewardBlocks, int percentileIndex) {
  final out = <BigInt>[];
  for (final rb in rewardBlocks) {
    if (rb == null) {
      continue;
    }
    final row = rb as List<dynamic>;
    if (percentileIndex >= row.length) {
      continue;
    }
    final cell = row[percentileIndex];
    if (cell == null) {
      continue;
    }
    if (cell is! BigInt) {
      continue;
    }
    if (cell > BigInt.zero) {
      out.add(cell);
    }
  }
  return out;
}

BigInt _etherDecimalStringToWei(String amount) {
  final s = amount.trim();
  if (s.isEmpty) {
    throw const FormatException('empty amount');
  }
  final parts = s.split('.');
  if (parts.length > 2) {
    throw const FormatException('invalid amount');
  }
  var whole = parts[0].isEmpty ? '0' : parts[0];
  var frac = parts.length > 1 ? parts[1] : '';
  if (frac.length > 18) {
    frac = frac.substring(0, 18);
  }
  frac = frac.padRight(18, '0');
  return BigInt.parse(whole) * BigInt.from(10).pow(18) + BigInt.parse(frac);
}

int _bumpedGasLimit(BigInt estimated) {
  final bumped = estimated * BigInt.from(115) ~/ BigInt.from(100);
  final v = bumped.toInt();
  return v.clamp(21000, 5000000);
}

/// 通过 JSON-RPC 拉取 fee history / gas price，估算原生转账矿工费档位。
class TransferFeeService {
  TransferFeeService(this._client);

  final Web3Client _client;

  Future<BigInt> _suggestPriorityFromRpc() async {
    try {
      final hex = await _client.makeRPCCall<String>('eth_maxPriorityFeePerGas');
      return hexToInt(hex);
    } catch (_) {
      return BigInt.from(1500000000);
    }
  }

  Future<NativeTransferFeeQuote> quoteNativeTransfer({
    required EthereumAddress from,
    required EthereumAddress to,
    required String amountEther,
  }) async {
    final value = EtherAmount.inWei(_etherDecimalStringToWei(amountEther));

    BigInt gasEst;
    try {
      gasEst = await _client.estimateGas(
        sender: from,
        to: to,
        value: value,
      );
    } catch (_) {
      gasEst = BigInt.from(21000);
    }
    final gasLimit = _bumpedGasLimit(gasEst);

    try {
      final history = await _client.getFeeHistory(
        6,
        atBlock: const BlockNum.current(),
        rewardPercentiles: [10, 50, 90],
      );
      final baseList = history['baseFeePerGas'];
      if (baseList is! List<dynamic> || baseList.isEmpty) {
        throw StateError('no baseFeePerGas');
      }
      final nextBase = baseList.last;
      if (nextBase is! BigInt) {
        throw StateError('baseFee type');
      }

      final rewardBlocks = history['reward'] as List<dynamic>? ?? [];
      var low = _medianBigInt(_tipsAtPercentile(rewardBlocks, 0));
      var med = _medianBigInt(_tipsAtPercentile(rewardBlocks, 1));
      var high = _medianBigInt(_tipsAtPercentile(rewardBlocks, 2));

      final rpcTip = await _suggestPriorityFromRpc();
      if (low <= BigInt.zero) {
        low = rpcTip * BigInt.from(85) ~/ BigInt.from(100);
      }
      if (med <= BigInt.zero) {
        med = rpcTip;
      }
      if (high <= BigInt.zero) {
        high = rpcTip * BigInt.from(125) ~/ BigInt.from(100);
      }
      if (med <= low) {
        med = low + BigInt.from(100000000);
      }
      if (high <= med) {
        high = med + BigInt.from(100000000);
      }

      return NativeTransferFeeQuote(
        gasLimit: gasLimit,
        isEip1559: true,
        nextBaseFeeWei: nextBase,
        tipLowWei: low,
        tipMedWei: med,
        tipHighWei: high,
      );
    } catch (_) {
      final gp = await _client.getGasPrice();
      final wei = gp.getInWei;
      final low = wei * BigInt.from(90) ~/ BigInt.from(100);
      final med = wei;
      final high = wei * BigInt.from(115) ~/ BigInt.from(100);
      return NativeTransferFeeQuote(
        gasLimit: gasLimit,
        isEip1559: false,
        nextBaseFeeWei: BigInt.zero,
        tipLowWei: low,
        tipMedWei: med,
        tipHighWei: high,
        legacyGasPriceWei: med,
      );
    }
  }
}

/// 供 [WalletController] 使用：按网络取池内 [Web3Client] 并报价。
Future<NativeTransferFeeQuote> quoteNativeTransferForNetwork({
  required EvmNetworkId network,
  required EthereumAddress from,
  required EthereumAddress to,
  required String amountEther,
}) {
  final client = EvmRpcPool.client(network);
  return TransferFeeService(client).quoteNativeTransfer(
    from: from,
    to: to,
    amountEther: amountEther,
  );
}
