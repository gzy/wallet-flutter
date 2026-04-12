import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../http/logging_http_client.dart';

/// 后端行情基址，可通过 `--dart-define=MARKET_API_BASE=https://...` 覆盖。
///
/// 文档：[Swagger 价格 · allPrice](https://api-wallet-test.uone.me/swagger-ui/index.html#/%E4%BB%B7%E6%A0%BC/allPrice)
/// 实际 OpenAPI 路径：`POST /api/app/price/all`，`data` 为 `{ "ETHUSDT": { "symbol", "price", "change24h", "ts" }, ... }`。
const String kMarketApiBase = String.fromEnvironment(
  'MARKET_API_BASE',
  defaultValue: 'https://api-wallet-test.uone.me',
);

class AppSymbolQuote {
  const AppSymbolQuote({required this.price, required this.change24h});

  final double price;

  /// 24h 涨跌幅（百分比数值，如 `2.779` 表示 +2.779%）。
  final double change24h;
}

/// 拉取应用聚合币价（U 本位交易对，如 ETHUSDT）。
class AppPriceService {
  AppPriceService({http.Client? httpClient})
      : _httpClient = httpClient ?? _defaultHttpClient();

  final http.Client _httpClient;

  static http.Client _defaultHttpClient() {
    final inner = http.Client();
    if (kDebugMode) {
      return LoggingHttpClient(
        inner,
        logName: 'AppPrice',
        maxLogBodyLength: 32000,
      );
    }
    return inner;
  }

  static Uri _allPricesUri() =>
      Uri.parse('$kMarketApiBase/api/app/price/all');

  /// 返回以交易对 key（如 `ETHUSDT`）为索引的报价；失败或 `code != 0` 时返回空 Map。
  Future<Map<String, AppSymbolQuote>> fetchAllPrices() async {
    try {
      final res = await _httpClient
          .post(
            _allPricesUri(),
            headers: const {'Content-Type': 'application/json'},
            body: '{}',
          )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        return {};
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        return {};
      }
      if (decoded['code'] != 0) {
        debugPrint('AppPriceService: code=${decoded['code']} msg=${decoded['message']}');
        return {};
      }

      final data = decoded['data'];
      if (data is! Map) {
        return {};
      }

      final out = <String, AppSymbolQuote>{};
      data.forEach((key, value) {
        if (value is! Map) {
          return;
        }
        final m = Map<String, dynamic>.from(value);
        final p = double.tryParse(m['price']?.toString() ?? '');
        if (p == null) {
          return;
        }
        final ch = double.tryParse(m['change24h']?.toString() ?? '') ?? 0;
        out[key.toString()] = AppSymbolQuote(price: p, change24h: ch);
      });
      return out;
    } catch (e, st) {
      debugPrint('AppPriceService.fetchAllPrices: $e\n$st');
      return {};
    }
  }

  /// 将原生币符号映射为接口中的交易对 key（当前列表均为 ETH → ETHUSDT）。
  static String usdtPairKeyForSymbol(String symbol) =>
      '${symbol.toUpperCase()}USDT';
}
