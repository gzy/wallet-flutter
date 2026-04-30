import 'package:flutter_test/flutter_test.dart';

import 'package:wallet_flutter/services/wallet/chain_rules.dart';

void main() {
  group('ChainRules kind detection', () {
    test('kindFromChainQuery', () {
      expect(ChainRules.kindFromChainQuery('TRX'), ChainKind.tron);
      expect(ChainRules.kindFromChainQuery('tron'), ChainKind.tron);
      expect(ChainRules.kindFromChainQuery('TRON_MAINNET'), ChainKind.tron);
      expect(ChainRules.kindFromChainQuery('ETH'), ChainKind.evm);
      expect(ChainRules.kindFromChainQuery(''), ChainKind.unknown);
    });

    test('kindFromChainType', () {
      expect(ChainRules.kindFromChainType('TRON'), ChainKind.tron);
      expect(ChainRules.kindFromChainType('EVM'), ChainKind.evm);
      expect(ChainRules.kindFromChainType(null), ChainKind.unknown);
    });
  });

  group('ChainRules address normalization', () {
    test('TRON: keep base58 address as-is', () {
      expect(
        ChainRules.normalizeAddressForStorage(ChainKind.tron, 'TXYZ'),
        'TXYZ',
      );
      expect(
        ChainRules.formatAddressForUi(ChainKind.tron, 'TXYZ'),
        'TXYZ',
      );
    });

    test('TRON: strip legacy 0x prefix if any', () {
      expect(
        ChainRules.normalizeAddressForStorage(ChainKind.tron, '0xTXYZ'),
        'TXYZ',
      );
      expect(
        ChainRules.formatAddressForUi(ChainKind.tron, '0xTXYZ'),
        'TXYZ',
      );
      expect(
        ChainRules.isValidAddress(ChainKind.tron, '0xTXYZ'),
        isFalse,
      );
    });

    test('EVM: normalize to lower-case with 0x', () {
      expect(
        ChainRules.normalizeAddressForStorage(ChainKind.evm, 'ABC'),
        '0xabc',
      );
      expect(
        ChainRules.normalizeAddressForStorage(ChainKind.evm, '0xABC'),
        '0xabc',
      );
      expect(
        ChainRules.formatAddressForUi(ChainKind.evm, 'abc'),
        '0xabc',
      );
    });
  });

  group('ChainRules badge label', () {
    test('badgeLabel', () {
      expect(ChainRules.badgeLabel(ChainKind.tron), 'TRON');
      expect(ChainRules.badgeLabel(ChainKind.evm), 'EVM');
      expect(ChainRules.badgeLabel(ChainKind.unknown), '—');
    });
  });
}
