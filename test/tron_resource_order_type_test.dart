import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_flutter/models/tron_resource_order_type.dart';

void main() {
  test('price query type constants', () {
    expect(TronResourceOrderType.buyNum, 'buy_num');
    expect(TronResourceOrderType.quickRent, 'quick_rent');
    expect(TronResourceOrderType.priceQueryForMode(true), 'buy_num');
    expect(TronResourceOrderType.priceQueryForMode(false), 'quick_rent');
    expect(TronResourceOrderType.buyNumMinCount, 5);
    expect(TronResourceOrderType.quickRentCount, 1);
  });
}
