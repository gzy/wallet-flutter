import 'dart:typed_data';

import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:bs58/bs58.dart' as bs58;
import 'package:dart_bip32_bip44/dart_bip32_bip44.dart';
import 'package:ed25519_hd_key/ed25519_hd_key.dart';
import 'package:ton_dart/ton_dart.dart';
import 'package:web3dart/crypto.dart' show hexToBytes;
import 'package:web3dart/web3dart.dart';

import '../../models/app_chain_config.dart';
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

/// BIP84 首个收款地址（主网 coin type 0）。
const String kBtcMainnetBip84Path = "m/84'/0'/0'/0/0";

/// BIP84 首个收款地址（测试网 coin type 1）。
const String kBtcTestnetBip84Path = "m/84'/1'/0'/0/0";

/// BIP44 Dogecoin 默认路径（coin type 3）。
const String kDogeDefaultDerivationPath = "m/44'/3'/0'/0/0";

/// BIP39 seed + SLIP-0010 Ed25519；coin type **607**（TON）。
///
/// [ed25519_hd_key] 的 SLIP-0010 实现**仅支持硬化派生**，路径里不能出现未带 `'` 的序号，
/// 否则会在 `derivePath` 时抛出 **`FormatException: Invalid number`**（旧路径曾误写 `…/0/0/0`）。
/// 默认账户采用 **`m/44'/607'/0'`**（与文档/常见多链钱包「首个 TON 账户」一致；见 TON BIP44）。
const String kTonDefaultDerivationPath = "m/44'/607'/0'";

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
  static List<int> _seedBytesFromMnemonic(String mnemonic) {
    var seedHex = MnemonicService.mnemonicToSeedHex(mnemonic).trim();
    if (seedHex.startsWith('0x') || seedHex.startsWith('0X')) {
      seedHex = seedHex.substring(2);
    }
    return BytesUtils.fromHexString(seedHex);
  }

  /// 与 [AppChainConfig] 的浏览器 / 名称 / chainCode 启发式判断是否为 BTC 测试网（用于 BIP84 coin type）。
  /// 与浏览器 / 链名 / `chainId` 判断 TON 是否为测试网（影响友好地址 test-only 标记与 v4 子钱包 id）。
  static bool tonTestOnlyHeuristic(AppChainConfig cfg) {
    final ex = (cfg.explorerUrl ?? '').toLowerCase();
    if (ex.contains('testnet') || ex.contains('sandbox')) {
      return true;
    }
    final n = cfg.chainName.toLowerCase();
    if (n.contains('test')) {
      return true;
    }
    final q = cfg.walletApiChainQuery.toUpperCase();
    if (q.contains('TEST')) {
      return true;
    }
    // 部分网关用全局 id -3 标识测试网（与 ton_dart [TonChainId.testnet] 一致）。
    if (cfg.chainId.trim() == '-3') {
      return true;
    }
    return false;
  }

  /// Dogecoin 测试网：与 BTC 相同，依据浏览器 / 链名 / chainCode 中的 testnet 等关键字。
  static bool dogeTestnetHeuristic(AppChainConfig cfg) => btcTestnetHeuristic(cfg);

  static bool btcTestnetHeuristic(AppChainConfig cfg) {
    final ex = (cfg.explorerUrl ?? '').toLowerCase();
    if (ex.contains('testnet') ||
        ex.contains('mempool.space/testnet') ||
        ex.contains('blockstream.info/testnet') ||
        ex.contains('signet')) {
      return true;
    }
    final q = cfg.walletApiChainQuery.toUpperCase();
    if (q.contains('TEST') || q == 'TBTC' || q == 'SBTC') {
      return true;
    }
    final n = cfg.chainName.toLowerCase();
    if (n.contains('test') || n.contains('signet')) {
      return true;
    }
    return false;
  }

  /// BIP84 P2WPKH 地址（bc1 / tb1），与 Ledger / MetaMask 等默认 Native SegWit 账户一致。
  /// BIP44 P2PKH（`D…` / 测试网 `n…`），与常见多链钱包 Dogecoin 默认账户一致。
  static String dogeP2pkhAddressFromMnemonic(
    String mnemonic, {
    required bool testnet,
  }) {
    final network =
        testnet ? DogecoinNetwork.testnet : DogecoinNetwork.mainnet;
    final priv = btcEcprivateFromMnemonicPath(mnemonic, kDogeDefaultDerivationPath);
    final p2pkh = priv.getPublic().toAddress();
    return DogeAddress.fromBaseAddress(p2pkh, network: network).address;
  }

  static String btcP2wpkhAddressFromMnemonic(
    String mnemonic, {
    required bool testnet,
  }) {
    final path = testnet ? kBtcTestnetBip84Path : kBtcMainnetBip84Path;
    final network = testnet ? BitcoinNetwork.testnet : BitcoinNetwork.mainnet;
    final priv = btcEcprivateFromMnemonicPath(mnemonic, path);
    return priv.getPublic().toSegwitAddress().toAddress(network);
  }

  static ECPrivate btcEcprivateFromMnemonicPath(String mnemonic, String path) {
    final seed = _seedBytesFromMnemonic(mnemonic);
    final root = Bip32Slip10Secp256k1.fromSeed(seed);
    final derived = root.derivePath(path) as Bip32Slip10Secp256k1;
    return ECPrivate.fromBytes(derived.privateKey.raw);
  }

  static Future<TonPrivateKey> tonPrivateKeyFromMnemonic(String mnemonic) async {
    final phrase = mnemonic.trim();
    final seedHex = MnemonicService.mnemonicToSeedHex(phrase);
    final normalizedHex = seedHex.startsWith('0x') || seedHex.startsWith('0X')
        ? seedHex
        : '0x$seedHex';
    final seedBytes = Uint8List.fromList(hexToBytes(normalizedHex));
    final kd = await ED25519_HD_KEY.derivePath(
      kTonDefaultDerivationPath,
      seedBytes,
    );
    return TonPrivateKey.fromBytes(Uint8List.fromList(kd.key));
  }

  /// 主网 / 测试网各生成一条 **用户友好地址**（URL-safe、非 bounceable）。
  ///
  /// 说明：主网常见以 **`UQ…`** 开头（非 bounceable）；**测试网** 地址在标志位里带 `test-only`，
  /// 经 Base64url 编码后常以 **`0f…` / `0Q…`** 等形式开头，与主网 `UQ…` 不同属**正常**，与链上账户一致即可。
  static Future<String> tonFriendlyAddressFromMnemonic(
    String mnemonic, {
    required bool testOnly,
  }) async {
    final pk = await tonPrivateKeyFromMnemonic(mnemonic);
    final chain = testOnly ? TonChainId.testnet : TonChainId.mainnet;
    final subWalletId = VersionedWalletConst.defaultSubWalletId + chain.workchain;
    final state = SubWalletVersionedWalletState(
      publicKey: pk.toPublicKey().toBytes(),
      version: WalletVersion.v4,
      subwallet: subWalletId,
    );
    final address = TonAddress.fromState(
      state: state.initialState(),
      workChain: chain.workchain,
      bounceable: false,
      testNet: testOnly,
    );
    return address.toFriendlyAddress(
      bounceable: false,
      testOnly: testOnly,
      urlSafe: true,
    );
  }

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
