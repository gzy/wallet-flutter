import 'package:flutter_test/flutter_test.dart';

import 'package:wallet_flutter/services/wallet/chain_rules.dart';
import 'package:wallet_flutter/services/wallet/hd_wallet_service.dart';

void main() {
  test(
    'BIP39 abandon…about @ m/44\'/144\'/0\'/0/0 matches ripple-keypairs (compressed pubkey hash)',
    () {
      const m =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      // 对照：tiny-secp256k1 bip32 path + noble secp compressed pubkey + ripple-keypairs deriveAddress
      const expected = 'rHsMGQEkVNJmpGWs8XUBoTBiAAbwxZN5v3';

      final a = HdWalletService.xrpAddressFromMnemonic(m);
      expect(a, expected);
      expect(ChainRules.isValidAddress(ChainKind.xrp, a), isTrue);
    },
  );
}
