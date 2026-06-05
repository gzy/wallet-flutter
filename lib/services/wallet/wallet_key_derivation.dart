import 'dart:isolate';
import 'dart:typed_data';

import '../../data/local/app_local_cache.dart';
import 'hd_wallet_service.dart';
import 'tron_utils.dart';

/// 助记词派生结果（可跨 isolate 传递）。
class WalletDerivedKeysResult {
  const WalletDerivedKeysResult({
    required this.evmPrivateKey,
    required this.addressHex,
    required this.tronPrivateKey,
    required this.tronAddress,
    required this.solanaAddress,
    required this.xrpAddress,
    required this.tonAddressMain,
    required this.tonAddressTest,
    required this.btcMainnetAddress,
    required this.btcTestnetAddress,
    required this.dogeMainnetAddress,
    required this.dogeTestnetAddress,
  });

  final Uint8List evmPrivateKey;
  final String addressHex;
  final Uint8List tronPrivateKey;
  final String tronAddress;
  final String? solanaAddress;
  final String? xrpAddress;
  final String? tonAddressMain;
  final String? tonAddressTest;
  final String? btcMainnetAddress;
  final String? btcTestnetAddress;
  final String? dogeMainnetAddress;
  final String? dogeTestnetAddress;

  DerivedAddressSnapshot toAddressSnapshot() {
    return DerivedAddressSnapshot(
      addressHex: addressHex,
      tronAddress: tronAddress,
      solanaAddress: solanaAddress,
      xrpAddress: xrpAddress,
      tonAddressMain: tonAddressMain,
      tonAddressTest: tonAddressTest,
      btcMainnetAddress: btcMainnetAddress,
      btcTestnetAddress: btcTestnetAddress,
      dogeMainnetAddress: dogeMainnetAddress,
      dogeTestnetAddress: dogeTestnetAddress,
    );
  }
}

/// 在独立 isolate 中派生各链密钥，避免阻塞启动页 loading 动画。
Future<WalletDerivedKeysResult> deriveWalletKeysInBackground(String mnemonic) {
  return Isolate.run(() => _deriveWalletKeys(mnemonic));
}

Future<WalletDerivedKeysResult> _deriveWalletKeys(String m) async {
  final credentials = HdWalletService.privateKeyFromMnemonic(m);
  final addressHex = credentials.address.hex;

  final tronPk = Uint8List.fromList(
    HdWalletService.tronPrivateKeyBytesFromMnemonic(m),
  );
  final tronAddress = tronAddressFromPrivateKeyBytes(tronPk);

  String? solanaAddress;
  String? xrpAddress;
  String? tonAddressMain;
  String? tonAddressTest;
  String? btcMainnetAddress;
  String? btcTestnetAddress;
  String? dogeMainnetAddress;
  String? dogeTestnetAddress;

  await Future.wait<void>([
    Future<void>(() async {
      try {
        solanaAddress = await HdWalletService.solanaAddressFromMnemonic(m);
      } catch (_) {
        solanaAddress = null;
      }
    }),
    Future<void>(() async {
      try {
        xrpAddress = HdWalletService.xrpAddressFromMnemonic(m);
      } catch (_) {
        xrpAddress = null;
      }
    }),
    Future<void>(() async {
      try {
        tonAddressMain = await HdWalletService.tonFriendlyAddressFromMnemonic(
          m,
          testOnly: false,
        );
      } catch (_) {
        tonAddressMain = null;
      }
    }),
    Future<void>(() async {
      try {
        tonAddressTest = await HdWalletService.tonFriendlyAddressFromMnemonic(
          m,
          testOnly: true,
        );
      } catch (_) {
        tonAddressTest = null;
      }
    }),
    Future<void>(() async {
      try {
        btcMainnetAddress = HdWalletService.btcP2wpkhAddressFromMnemonic(
          m,
          testnet: false,
        );
      } catch (_) {
        btcMainnetAddress = null;
      }
    }),
    Future<void>(() async {
      try {
        btcTestnetAddress = HdWalletService.btcP2wpkhAddressFromMnemonic(
          m,
          testnet: true,
        );
      } catch (_) {
        btcTestnetAddress = null;
      }
    }),
    Future<void>(() async {
      try {
        dogeMainnetAddress = HdWalletService.dogeP2pkhAddressFromMnemonic(
          m,
          testnet: false,
        );
      } catch (_) {
        dogeMainnetAddress = null;
      }
    }),
    Future<void>(() async {
      try {
        dogeTestnetAddress = HdWalletService.dogeP2pkhAddressFromMnemonic(
          m,
          testnet: true,
        );
      } catch (_) {
        dogeTestnetAddress = null;
      }
    }),
  ]);

  return WalletDerivedKeysResult(
    evmPrivateKey: Uint8List.fromList(credentials.privateKey),
    addressHex: addressHex,
    tronPrivateKey: tronPk,
    tronAddress: tronAddress,
    solanaAddress: solanaAddress,
    xrpAddress: xrpAddress,
    tonAddressMain: tonAddressMain,
    tonAddressTest: tonAddressTest,
    btcMainnetAddress: btcMainnetAddress,
    btcTestnetAddress: btcTestnetAddress,
    dogeMainnetAddress: dogeMainnetAddress,
    dogeTestnetAddress: dogeTestnetAddress,
  );
}
