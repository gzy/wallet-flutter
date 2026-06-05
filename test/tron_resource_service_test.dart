import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wallet_flutter/models/tron_resource_order_type.dart';
import 'package:wallet_flutter/models/tron_resource_preorder_dto.dart';
import 'package:wallet_flutter/services/wallet/tron_resource_service.dart';

void main() {
  group('TronResourceService', () {
    test('fetchPrice parses tier map', () async {
      final client = MockClient((request) async {
        expect(request.url.path, endsWith('/api/app/trx/resource/price'));
        expect(request.url.queryParameters['type'], TronResourceOrderType.buyNum);
        return http.Response(
          jsonEncode({
            'code': 0,
            'message': 'ok',
            'data': {
              '131000': {
                'energyType': 'buy_num',
                'resourceValue': 131000,
                'crypto': 'TRX',
                'price': 3.6,
              },
            },
          }),
          200,
        );
      });
      final svc = TronResourceService(httpClient: client);
      final tiers = await svc.fetchPrice(TronResourceOrderType.buyNum);
      expect(tiers.length, 1);
      expect(tiers.first.resourceValue, 131000);
      expect(tiers.first.price, 3.6);
      expect(tiers.first.energyType, 'buy_num');
    });

    test('fetchAccountResource returns vo on code 0', () async {
      final client = MockClient((request) async {
        expect(request.url.path, endsWith('/api/app/trx/resource/detail'));
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': {
              'address': 'TAddr',
              'energyAvailable': 0,
              'energyLimit': 100,
              'bandwidthAvailable': 600,
              'bandwidthLimit': 600,
            },
          }),
          200,
        );
      });
      final svc = TronResourceService(httpClient: client);
      final r = await svc.fetchAccountResource('TAddr');
      expect(r?.energyAvailable, 0);
      expect(r?.bandwidthAvailable, 600);
    });

    test('preorder throws on non-zero code', () async {
      final client = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(jsonEncode({'code': 1, 'message': '余额不足'})),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final svc = TronResourceService(httpClient: client);
      expect(
        svc.preorder(
          const TronResourcePreOrderDto(
            energyType: 'buy_num',
            resourceValue: 131000,
            payerAddress: 'Tp',
            toAddress: 'Tt',
            count: 5,
          ),
        ),
        throwsA(isA<StateError>().having((e) => e.message, 'message', '余额不足')),
      );
    });

    test('confirmOrder sends orderId and data', () async {
      String? body;
      final client = MockClient((request) async {
        body = request.body;
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': {
              'orderId': 'o1',
              'txHash': 'abc',
              'totalAmount': 3.6,
              'crypto': 'TRX',
            },
          }),
          200,
        );
      });
      final svc = TronResourceService(httpClient: client);
      final r = await svc.confirmOrder(orderId: 'o1', signedData: '{"signed":true}');
      expect(r.txHash, 'abc');
      final decoded = jsonDecode(body!) as Map;
      expect(decoded['orderId'], 'o1');
      expect(decoded['data'], '{"signed":true}');
    });
  });
}
