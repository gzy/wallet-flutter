import 'package:flutter_test/flutter_test.dart';

import 'package:wallet_flutter/services/wallet/hd_wallet_service.dart';
import 'package:wallet_flutter/services/wallet/mnemonic_service.dart';

void main() {
  test('TON friendly address derives from BIP39 seed (SLIP-0010 hardened path)', () async {
    const m =
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
    expect(MnemonicService.validateMnemonic(m), isTrue);
    final main = await HdWalletService.tonFriendlyAddressFromMnemonic(
      m,
      testOnly: false,
    );
    final test = await HdWalletService.tonFriendlyAddressFromMnemonic(
      m,
      testOnly: true,
    );
    expect(main, isNotEmpty);
    expect(test, isNotEmpty);
    expect(main, isNot(equals(test)));
  });
}
