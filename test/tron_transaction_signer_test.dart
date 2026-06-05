import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_flutter/services/wallet/tron_transaction_signer.dart';

void main() {
  group('TronTransactionSigner', () {
    test('extractRawDataHex reads snake_case and camelCase', () {
      expect(
        TronTransactionSigner.extractRawDataHex({
          'raw_data_hex': '0a0201',
        }),
        '0a0201',
      );
      expect(
        TronTransactionSigner.extractRawDataHex({
          'rawDataHex': '0a0202',
        }),
        '0a0202',
      );
      expect(
        TronTransactionSigner.extractRawDataHex({
          'transaction': {'raw_data_hex': '0a0203'},
        }),
        '0a0203',
      );
    });
  });
}
