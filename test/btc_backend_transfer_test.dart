import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_flutter/services/wallet/btc_backend_transfer.dart';
import 'package:wallet_flutter/services/wallet/wallet_estimate_gas_service.dart';
import 'package:wallet_flutter/services/wallet/wallet_gas_price_service.dart';

void main() {
  group('BtcBackendTransfer.normalizeCreateTransactionPayload', () {
    test('unwraps nested transaction map and aliases snake_case keys', () {
      final out = BtcBackendTransfer.normalizeCreateTransactionPayload({
        'transaction': {
          'tx_hex': '0100000001',
          'tx_inputs': [
            {
              'prev_tx_hex': '0200000001',
              'vout': 0,
            },
          ],
        },
      });

      expect(out['txHex'], '0100000001');
      expect(out['txInput'], isA<List>());
      final row = out['txInput'][0] as Map;
      expect(row['txHex'], '0200000001');
      expect(row['index'], 0);
    });

    test('aliases txInputs and inputs to txInput', () {
      final out = BtcBackendTransfer.normalizeCreateTransactionPayload({
        'txHex': '0100000001',
        'inputs': [
          {'txHex': '0200000001', 'index': 1},
        ],
      });

      expect(out['txInput'], isA<List>());
      expect((out['txInput'] as List).length, 1);
    });

    test('wraps PSBT base64 string payload', () {
      final out = BtcBackendTransfer.normalizeCreateTransactionPayload('cHNidP8B');
      expect(out['psbtBase64'], 'cHNidP8B');
    });

    test('vout scriptPubKey.hex deserializes without extra push prefix', () {
      const p2pkh =
          '76a914df98f35823a71496007c11b9a9e83ed8e1503b5388ac';
      final script = BtcBackendTransfer.scriptPubKeyFromVoutRowForTest({
        'scriptPubKey': {'hex': p2pkh},
      });
      expect(script.toHex(), p2pkh);
      expect(script.toHex().startsWith('19'), isFalse);
    });

    test('unwraps jsonrpc decoderawtransaction result', () {
      final out = BtcBackendTransfer.normalizeCreateTransactionPayload({
        'result': {
          'vsize': 119,
          'vin': [
            {'txid': '4259b78efe248fbb6ac5f278f368996c5cffd6826a0e2ef4b25600d22ab31d12', 'vout': 0, 'sequence': 4294967295},
          ],
          'vout': [
            {
              'value': 1.0,
              'scriptPubKey': {'hex': '76a914' + '00' * 20 + '88ac'},
            },
          ],
        },
      });
      expect(out['vin'], isA<List>());
      expect(BtcBackendTransfer.parseTxVsizeFromDecoded(out), 119);
    });
  });

  group('WalletEstimateGasService.computeUtxoFeeCoin', () {
    test('BTC: sat/vB integer rate', () {
      final fee = WalletEstimateGasService.computeUtxoFeeCoin(
        txSize: 119,
        quote: kBtcFeeQuoteFallbackSatPerVbyte,
      );
      expect(fee, closeTo(119 * 5 / 1e8, 1e-12));
    });

    test('DOGE: coin per vB decimal rate', () {
      final quote = WalletBtcFeeQuote(
        slowSatPerVbyte: Decimal.parse('0.00017802'),
        mediumSatPerVbyte: Decimal.parse('0.00017802'),
        fastSatPerVbyte: Decimal.parse('0.00017802'),
      );
      final fee = WalletEstimateGasService.computeUtxoFeeCoin(
        txSize: 226,
        quote: quote,
      );
      expect(fee, closeTo(226 * 0.00017802, 1e-10));
    });
  });
}
