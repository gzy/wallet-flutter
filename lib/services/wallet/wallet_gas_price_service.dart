import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../http/http_clients.dart';
import '../market/app_price_service.dart' show kMarketApiBase;

class WalletGasPriceQuote {
  const WalletGasPriceQuote({
    required this.slowGasPriceGwei,
    required this.mediumGasPriceGwei,
    required this.fastGasPriceGwei,
    required this.suggestBaseFeeGwei,
  });

  final Decimal slowGasPriceGwei;
  final Decimal mediumGasPriceGwei;
  final Decimal fastGasPriceGwei;
  final Decimal suggestBaseFeeGwei;
}

Decimal? _asDecimal(Object? v) {
  if (v == null) return null;
  if (v is Decimal) return v;
  try {
    return Decimal.parse(v.toString());
  } catch (_) {
    return null;
  }
}

Decimal? _pickDecimal(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = _asDecimal(m[k]);
    if (v != null) return v;
  }
  return null;
}

/// 后端矿工费报价（OpenAPI：`GET /api/app/wallet/gasPrice?chain=`）。
class WalletGasPriceService {
  WalletGasPriceService({http.Client? httpClient})
      : _httpClient = httpClient ?? _defaultClient();

  final http.Client _httpClient;

  static http.Client _defaultClient() {
    return HttpClients.create(
        logName: 'WalletGasPrice', maxLogBodyLength: 12000);
  }

  static Uri _buildUri({required String chain}) {
    return Uri.parse('$kMarketApiBase/api/app/wallet/gasPrice').replace(
      queryParameters: {'chain': chain},
    );
  }

  /// 成功且 `code == 0` 时返回报价；HTTP/解析/`code != 0` 时返回 `null`。
  Future<WalletGasPriceQuote?> fetchGasPrice({required String chain}) async {
    try {
      final res = await _httpClient.get(
        _buildUri(chain: chain),
        headers: const {'Accept': '*/*'},
      ).timeout(const Duration(seconds: 12));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (kDebugMode) {
          debugPrint('WalletGasPriceService: HTTP ${res.statusCode}');
        }
        return null;
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      if (decoded['code'] != 0) {
        if (kDebugMode) {
          debugPrint(
            'WalletGasPriceService: code=${decoded['code']} msg=${decoded['message']}',
          );
        }
        return null;
      }

      final data = decoded['data'];
      if (data is! Map) {
        return null;
      }
      final m = Map<String, dynamic>.from(data);
      final slow = _pickDecimal(m, const [
        'slowGasPrice',
        'slow_gas_price',
        'slow',
        'low',
      ]);
      final med = _pickDecimal(m, const [
        'mediumGasPrice',
        'medium_gas_price',
        'medium',
        'normal',
      ]);
      final fast = _pickDecimal(m, const [
        'fastGasPrice',
        'fast_gas_price',
        'fast',
        'high',
      ]);
      final base = _pickDecimal(m, const [
        'suggestBaseFee',
        'suggest_base_fee',
        'baseFee',
        'base_fee',
      ]);
      if (slow == null || med == null || fast == null || base == null) {
        return null;
      }

      return WalletGasPriceQuote(
        slowGasPriceGwei: slow,
        mediumGasPriceGwei: med,
        fastGasPriceGwei: fast,
        suggestBaseFeeGwei: base,
      );
    } catch (e, st) {
      debugPrint('WalletGasPriceService.fetchGasPrice: $e\n$st');
      return null;
    }
  }
}
