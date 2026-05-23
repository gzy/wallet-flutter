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

/// BTC：`GET /api/app/wallet/gasPrice?chain=BTC` 返回的 **sat/vB** 档位（字段名可与 EVM 一致，仅单位不同）。
class WalletBtcFeeQuote {
  const WalletBtcFeeQuote({
    required this.slowSatPerVbyte,
    required this.mediumSatPerVbyte,
    required this.fastSatPerVbyte,
  });

  final Decimal slowSatPerVbyte;
  final Decimal mediumSatPerVbyte;
  final Decimal fastSatPerVbyte;
}

/// `gasPrice` 成功但无 `data` / 无档位字段时的展示用占位（sat/vB）；真实费率应由后端在 `data` 中返回。
final WalletBtcFeeQuote kBtcFeeQuoteFallbackSatPerVbyte = WalletBtcFeeQuote(
  slowSatPerVbyte: Decimal.fromInt(2),
  mediumSatPerVbyte: Decimal.fromInt(5),
  fastSatPerVbyte: Decimal.fromInt(15),
);

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

WalletBtcFeeQuote? _tryParseBtcSatPerVbyteTiers(Map<String, dynamic> m) {
  final slow = _pickDecimal(m, const [
    'slowSatPerVbyte',
    'slow_sat_per_vbyte',
    'slowFeeRate',
    'slow_fee_rate',
    'slowGasPrice',
    'slow_gas_price',
    'slow',
    'low',
  ]);
  final med = _pickDecimal(m, const [
    'mediumSatPerVbyte',
    'medium_sat_per_vbyte',
    'mediumFeeRate',
    'medium_fee_rate',
    'mediumGasPrice',
    'medium_gas_price',
    'medium',
    'normal',
  ]);
  final fast = _pickDecimal(m, const [
    'fastSatPerVbyte',
    'fast_sat_per_vbyte',
    'fastFeeRate',
    'fast_fee_rate',
    'fastGasPrice',
    'fast_gas_price',
    'fast',
    'high',
  ]);
  if (slow == null || med == null || fast == null) {
    return null;
  }
  return WalletBtcFeeQuote(
    slowSatPerVbyte: slow,
    mediumSatPerVbyte: med,
    fastSatPerVbyte: fast,
  );
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

  /// 与 [fetchGasPrice] 同一接口；解析为 **sat/vB**（不要求 `suggestBaseFee`）。
  ///
  /// 若 `code==0` 但缺少 `data` 或档位字段（你方当前 BTC 响应仅 `message`），先尝试根级 Map，
  /// 再退回 [kBtcFeeQuoteFallbackSatPerVbyte] 以便与 `estimateGas` 的 `txSize` 组合展示估算。
  Future<WalletBtcFeeQuote?> fetchBtcFeeQuote({required String chain}) async {
    try {
      final res = await _httpClient.get(
        _buildUri(chain: chain),
        headers: const {'Accept': '*/*'},
      ).timeout(const Duration(seconds: 12));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (kDebugMode) {
          debugPrint('WalletGasPriceService(BTC): HTTP ${res.statusCode}');
        }
        return null;
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic> || decoded['code'] != 0) {
        if (kDebugMode) {
          debugPrint(
            'WalletGasPriceService(BTC): code=${decoded is Map ? decoded['code'] : 'n/a'}',
          );
        }
        return null;
      }

      final data = decoded['data'];
      if (data is Map) {
        final fromData = _tryParseBtcSatPerVbyteTiers(
          Map<String, dynamic>.from(data),
        );
        if (fromData != null) {
          return fromData;
        }
      }

      final root = Map<String, dynamic>.from(decoded);
      root.remove('code');
      root.remove('message');
      final fromRoot = _tryParseBtcSatPerVbyteTiers(root);
      if (fromRoot != null) {
        return fromRoot;
      }

      if (kDebugMode) {
        debugPrint(
          'WalletGasPriceService(BTC): 无 data 费率字段，使用占位 '
          '${kBtcFeeQuoteFallbackSatPerVbyte.slowSatPerVbyte}/'
          '${kBtcFeeQuoteFallbackSatPerVbyte.mediumSatPerVbyte}/'
          '${kBtcFeeQuoteFallbackSatPerVbyte.fastSatPerVbyte} sat/vB',
        );
      }
      return kBtcFeeQuoteFallbackSatPerVbyte;
    } catch (e, st) {
      debugPrint('WalletGasPriceService.fetchBtcFeeQuote: $e\n$st');
      return null;
    }
  }
}
