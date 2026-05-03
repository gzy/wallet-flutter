import 'dart:typed_data';

import 'package:bs58/bs58.dart' as bs58;
import 'package:dart_bip32_bip44/dart_bip32_bip44.dart';
import 'package:ed25519_hd_key/ed25519_hd_key.dart';
import 'package:web3dart/crypto.dart' show hexToBytes;
import 'package:web3dart/web3dart.dart';

import 'mnemonic_service.dart';
import 'xrp_utils.dart';

/// BIP44 以太坊默认路径首个地址
const String kEthDefaultDerivationPath = "m/44'/60'/0'/0/0";

/// BIP44 Tron 默认路径首个地址
const String kTronDefaultDerivationPath = "m/44'/195'/0'/0/0";

/// BIP44 Ripple (XRP) 默认路径首个地址（coin type 144）。
const String kXrpDefaultDerivationPath = "m/44'/144'/0'/0/0";

/// SafePal / Phantom 等常用 Solana 路径（测试网·主网同一套路径规则）。
const String kSolanaDefaultDerivationPath = "m/44'/501'/0'/0'";

class HdWalletService {
  HdWalletService._();

  /// 从助记词派生标准以太坊私钥（与 MetaMask 等默认账户一致）
  static EthPrivateKey privateKeyFromMnemonic(String mnemonic) {
    final seedHex = MnemonicService.mnemonicToSeedHex(mnemonic);
    final chain = Chain.seed(seedHex);
    final key = chain.forPath(kEthDefaultDerivationPath);
    if (key is! ExtendedPrivateKey) {
      throw StateError(
          'Expected ExtendedPrivateKey at $kEthDefaultDerivationPath');
    }
    return EthPrivateKey.fromInt(key.key!);
  }

  /// 从助记词派生 Tron 私钥 bytes（32 字节，大端）。
  static List<int> tronPrivateKeyBytesFromMnemonic(String mnemonic) {
    final seedHex = MnemonicService.mnemonicToSeedHex(mnemonic);
    final chain = Chain.seed(seedHex);
    final key = chain.forPath(kTronDefaultDerivationPath);
    if (key is! ExtendedPrivateKey) {
      throw StateError(
          'Expected ExtendedPrivateKey at $kTronDefaultDerivationPath');
    }
    final bi = key.key!;
    final out = List<int>.filled(32, 0);
    var x = bi;
    for (var i = 31; i >= 0; i--) {
      out[i] = (x & BigInt.from(0xff)).toInt();
      x = x >> 8;
    }
    return out;
  }

  /// 从助记词派生 XRP Ledger Classic 地址（`r...`，secp256k1 + SHA256/RMD160）。
  ///
  /// 路径 [kXrpDefaultDerivationPath] 与 Ledger、常见多链钱包默认账户一致。
  static List<int> xrpPrivateKeyBytesFromMnemonic(String mnemonic) {
    final seedHex = MnemonicService.mnemonicToSeedHex(mnemonic);
    final chain = Chain.seed(seedHex);
    final key = chain.forPath(kXrpDefaultDerivationPath);
    if (key is! ExtendedPrivateKey) {
      throw StateError(
          'Expected ExtendedPrivateKey at $kXrpDefaultDerivationPath');
    }
    final bi = key.key!;
    final out = List<int>.filled(32, 0);
    var x = bi;
    for (var i = 31; i >= 0; i--) {
      out[i] = (x & BigInt.from(0xff)).toInt();
      x = x >> 8;
    }
    return out;
  }

  static String xrpAddressFromMnemonic(String mnemonic) {
    return xrpAddressFromPrivateKeyBytes(
      Uint8List.fromList(xrpPrivateKeyBytesFromMnemonic(mnemonic)),
    );
  }

  /// Ed25519 派生收款地址（Base58 · 32 字节公钥）；与 SafePal 展示 `m/44'/501'/0'/0'` 对齐。
  static Future<String> solanaAddressFromMnemonic(String mnemonic) async {
    final phrase = mnemonic.trim();
    final seedHex = MnemonicService.mnemonicToSeedHex(phrase);
    final normalizedHex = seedHex.startsWith('0x') || seedHex.startsWith('0X')
        ? seedHex
        : '0x$seedHex';
    final seedBytes = Uint8List.fromList(hexToBytes(normalizedHex));
    final kd = await ED25519_HD_KEY.derivePath(
      kSolanaDefaultDerivationPath,
      seedBytes,
    );
    final pub = await ED25519_HD_KEY.getPublicKey(kd.key, false);
    return bs58.base58.encode(Uint8List.fromList(pub));
  }
}
