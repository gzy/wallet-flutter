import 'package:flutter_test/flutter_test.dart';

import 'package:wallet_flutter/services/wallet/tron_utils.dart';

void main() {
  test('isValidTronAddress returns false for invalid base58 chars (no throw)',
      () {
    // Base58 alphabet excludes 0, O, I, l. Using "0" should not throw.
    expect(isValidTronAddress('T0INVALIDADDRESS'), isFalse);
  });
}
