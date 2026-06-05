import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/tron_account_resource_vo.dart';
import '../../models/tron_resource_confirm_vo.dart';
import '../../models/tron_resource_preorder_dto.dart';
import '../../models/tron_resource_preorder_vo.dart';
import '../../models/tron_resource_price_tier.dart';
import '../http/http_clients.dart';
import 'tron_resource_paths.dart';

/// 波场资源租赁 API：`detail` / `price` / `preorder` / `confirmOrder`。
class TronResourceService {
  TronResourceService({http.Client? httpClient})
      : _httpClient = httpClient ?? _defaultClient();

  final http.Client _httpClient;

  static http.Client _defaultClient() {
    return HttpClients.create(
      logName: 'TronResource',
      maxLogBodyLength: 20000,
    );
  }

  static const _headers = {
    'Accept': '*/*',
    'Content-Type': 'application/json',
  };

  Future<TronAccountResourceVo?> fetchAccountResource(String address) async {
    try {
      final res = await _httpClient
          .get(TronResourcePaths.detail(address: address))
          .timeout(const Duration(seconds: 20));
      return _parseData(res.body, TronAccountResourceVo.fromJson);
    } catch (e, st) {
      debugPrint('TronResourceService.fetchAccountResource: $e\n$st');
      return null;
    }
  }

  /// [type]：`TronResourceOrderType.buyNum` | `TronResourceOrderType.quickRent`
  Future<List<TronResourcePriceTier>> fetchPrice(String type) async {
    try {
      final res = await _httpClient
          .get(TronResourcePaths.price(type: type))
          .timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return [];
      if (decoded['code'] != 0) return [];
      final data = decoded['data'];
      if (data is! Map) return [];
      final tiers = <TronResourcePriceTier>[];
      for (final entry in data.entries) {
        if (entry.value is! Map) continue;
        final keyRv = int.tryParse(entry.key.toString());
        tiers.add(
          TronResourcePriceTier.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
            resourceValueFromKey: keyRv,
          ),
        );
      }
      tiers.sort((a, b) => a.resourceValue.compareTo(b.resourceValue));
      return tiers;
    } catch (e, st) {
      debugPrint('TronResourceService.fetchPrice: $e\n$st');
      return [];
    }
  }

  Future<TronResourcePreOrderVo> preorder(TronResourcePreOrderDto dto) async {
    final res = await _httpClient
        .post(
          TronResourcePaths.preorder(),
          headers: _headers,
          body: jsonEncode(dto.toJson()),
        )
        .timeout(const Duration(seconds: 25));
    return _parseDataOrThrow(res.body, TronResourcePreOrderVo.fromJson);
  }

  Future<TronResourceConfirmVo> confirmOrder({
    required String orderId,
    required String signedData,
  }) async {
    final res = await _httpClient
        .post(
          TronResourcePaths.confirmOrder(),
          headers: _headers,
          body: jsonEncode({
            'orderId': orderId,
            'data': signedData,
          }),
        )
        .timeout(const Duration(seconds: 25));
    return _parseDataOrThrow(res.body, TronResourceConfirmVo.fromJson);
  }

  T? _parseData<T>(
    String body,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['code'] != 0) return null;
    final data = decoded['data'];
    if (data is! Map) return null;
    return fromJson(Map<String, dynamic>.from(data));
  }

  T _parseDataOrThrow<T>(
    String body,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('响应格式错误');
    }
    if (decoded['code'] != 0) {
      final msg = decoded['message']?.toString() ?? '请求失败';
      throw StateError(msg);
    }
    final data = decoded['data'];
    if (data is! Map) {
      throw StateError('响应缺少 data');
    }
    return fromJson(Map<String, dynamic>.from(data));
  }
}
