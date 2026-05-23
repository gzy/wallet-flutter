import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_flutter/services/wallet/chain_rules.dart';

void main() {
  test('kindFromChainQuery recognizes BTC', () {
    expect(ChainRules.kindFromChainQuery('BTC'), ChainKind.btc);
    expect(ChainRules.kindFromChainQuery('bitcoin'), ChainKind.btc);
    expect(ChainRules.kindFromChainQuery('ETH'), ChainKind.evm);
  });

  test('kindFromChainType recognizes BTC', () {
    expect(ChainRules.kindFromChainType('BTC'), ChainKind.btc);
    expect(ChainRules.kindFromChainType('Bitcoin'), ChainKind.btc);
  });
}
