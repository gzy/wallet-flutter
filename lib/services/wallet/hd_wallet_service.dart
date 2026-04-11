import 'package:dart_bip32_bip44/dart_bip32_bip44.dart';
import 'package:web3dart/web3dart.dart';

import 'mnemonic_service.dart';

/// BIP44 以太坊默认路径首个地址
const String kEthDefaultDerivationPath = "m/44'/60'/0'/0/0";

class HdWalletService {
  HdWalletService._();

  /// 从助记词派生标准以太坊私钥（与 MetaMask 等默认账户一致）
  static EthPrivateKey privateKeyFromMnemonic(String mnemonic) {
    final seedHex = MnemonicService.mnemonicToSeedHex(mnemonic);
    final chain = Chain.seed(seedHex);
    final key = chain.forPath(kEthDefaultDerivationPath);
    if (key is! ExtendedPrivateKey) {
      throw StateError('Expected ExtendedPrivateKey at $kEthDefaultDerivationPath');
    }
    return EthPrivateKey.fromInt(key.key!);
  }
}
