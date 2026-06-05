import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../http/http_clients.dart';
import '../market/app_price_service.dart' show kMarketApiBase;
import 'wallet_gas_price_service.dart';

/// 后端 `POST /api/app/wallet/estimateGas`：返回 `gasLimit` 等，用于不依赖链上 RPC 估算手续费。
class WalletEstimateGasService {
  WalletEstimateGasService({http.Client? httpClient})
      : _httpClient = httpClient ?? _defaultClient();

  final http.Client _httpClient;

  static http.Client _defaultClient() {
    return HttpClients.create(
        logName: 'WalletEstimateGas', maxLogBodyLength: 20000);
  }

  static Uri _uri() => Uri.parse('$kMarketApiBase/api/app/wallet/estimateGas');
  static Uri _uriV2() =>
      Uri.parse('$kMarketApiBase/api/app/wallet/estimateGasV2');

  static bool _looksLikeStaleSocketOrTls(Object e) {
    final s = e.toString().toUpperCase();
    return s.contains('WRONG_VERSION_NUMBER') ||
        s.contains('HANDSHAKE') ||
        s.contains('TLSV1_ALERT') ||
        s.contains('CONNECTION RESET') ||
        s.contains('BROKEN PIPE') ||
        s.contains('SOCKET_EXCEPTION');
  }

  /// 与 [WalletBalanceService] 一致：对 TLS/半开连接类错误重试，第 2 次起强制 `Connection: close`。
  Future<Object?> _postEstimateData({
    required Uri uri,
    required Map<String, dynamic> payload,
    required String logLabel,
  }) async {
    const maxAttempts = 3;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final headers = <String, String>{
          'Accept': '*/*',
          'Content-Type': 'application/json',
          if (attempt > 0) 'connection': 'close',
        };
        final res = await _httpClient
            .post(
              uri,
              headers: headers,
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 25));
        if (res.statusCode < 200 || res.statusCode >= 300) {
          if (kDebugMode) {
            debugPrint('WalletEstimateGasService$logLabel: HTTP ${res.statusCode}');
          }
          return null;
        }
        final decoded = jsonDecode(res.body);
        if (decoded is! Map<String, dynamic> || decoded['code'] != 0) {
          if (kDebugMode) {
            debugPrint(
              'WalletEstimateGasService$logLabel: code=${decoded is Map ? decoded['code'] : 'n/a'}',
            );
          }
          return null;
        }
        return decoded['data'];
      } catch (e, st) {
        final retryable = attempt < maxAttempts - 1 &&
            (e is SocketException ||
                e is HandshakeException ||
                e is TlsException ||
                _looksLikeStaleSocketOrTls(e));
        if (retryable) {
          if (kDebugMode) {
            debugPrint(
              'WalletEstimateGasService$logLabel: retry ${attempt + 1} after $e',
            );
          }
          await Future<void>.delayed(
            Duration(milliseconds: 120 * (attempt + 1)),
          );
          continue;
        }
        debugPrint('WalletEstimateGasService$logLabel: $e\n$st');
        return null;
      }
    }
    return null;
  }

  /// `code==0` 时返回 [data]（一般为 Map，含 `gasLimit`），否则 `null`。
  Future<Object?> estimateGas({
    required String chain,
    required String coin,
    required String ownerAddress,
    required String toAddress,
    required num amount,
  }) async {
    final payload = <String, dynamic>{
      'chain': chain,
      'coin': coin,
      'ownerAddress': ownerAddress,
      'toAddress': toAddress,
      'amount': amount,
    };
    return _postEstimateData(
      uri: _uri(),
      payload: payload,
      logLabel: '',
    );
  }

  /// 后端 `POST /api/app/wallet/estimateGasV2`：参数与旧版一致，EVM 取 `data.gasLimit`。
  ///
  /// `code==0` 时返回 [data]（一般为 Map，含 `gasLimit`），否则 `null`。
  Future<Object?> estimateGasV2({
    required String chain,
    required String coin,
    required String ownerAddress,
    required String toAddress,
    required num amount,
  }) async {
    final payload = <String, dynamic>{
      'chain': chain,
      'coin': coin,
      'ownerAddress': ownerAddress,
      'toAddress': toAddress,
      'amount': amount,
    };
    return _postEstimateData(
      uri: _uriV2(),
      payload: payload,
      logLabel: '(V2)',
    );
  }

  /// 优先使用 V2；若 V2 无法解析出 gasLimit，则回退旧版。
  ///
  /// 返回值与 [estimateGas]/[estimateGasV2] 一致：成功时返回 `data`，否则 `null`。
  Future<Object?> estimateGasPreferV2({
    required String chain,
    required String coin,
    required String ownerAddress,
    required String toAddress,
    required num amount,
    bool requireGasLimit = true,
  }) async {
    final v2 = await estimateGasV2(
      chain: chain,
      coin: coin,
      ownerAddress: ownerAddress,
      toAddress: toAddress,
      amount: amount,
    );
    final v2OkGas = parseGasLimit(v2) != null;
    final v2OkBtc = parseTxSize(v2) != null;
    if (v2 != null && (!requireGasLimit || v2OkGas || v2OkBtc)) {
      return v2;
    }
    return estimateGas(
      chain: chain,
      coin: coin,
      ownerAddress: ownerAddress,
      toAddress: toAddress,
      amount: amount,
    );
  }

  static int? parseGasLimit(Object? data) {
    if (data == null) return null;
    if (data is int) {
      return data > 0 ? data : null;
    }
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      final v = m['gasLimit'] ?? m['gas'] ?? m['gas_limit'];
      if (v is int) return v > 0 ? v : null;
      if (v is num) {
        final i = v.round();
        return i > 0 ? i : null;
      }
      if (v is String) {
        final p = int.tryParse(v);
        if (p != null && p > 0) return p;
      }
    }
    return null;
  }

  /// BTC 等 UTXO 链：`estimateGas` / `estimateGasV2` 的 `data.txSize`（虚拟体积 vB 等），用于 `txSize * 费率`。
  static int? parseTxSize(Object? data) {
    if (data == null) return null;
    if (data is int) {
      return data > 0 ? data : null;
    }
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      final v = m['txSize'] ??
          m['tx_size'] ??
          m['vsize'] ??
          m['virtualSize'] ??
          m['virtual_size'] ??
          m['size'];
      if (v is int) return v > 0 ? v : null;
      if (v is num) {
        final i = v.round();
        return i > 0 ? i : null;
      }
      if (v is String) {
        final p = int.tryParse(v.trim());
        if (p != null && p > 0) return p;
      }
    }
    return null;
  }

  /// UTXO 链：`estimateGas` / `estimateGasV2` 的 `data` 里常见手续费字段（主单位小数）。
  static double? parseNetworkFee(Object? data) {
    if (data == null) {
      return null;
    }
    if (data is num) {
      return data.toDouble();
    }
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      for (final k in const [
        'transactionFee',
        'fee',
        'networkFee',
        'gasFee',
        'minerFee',
        'estimatedFee',
      ]) {
        final v = m[k];
        if (v is num) {
          return v.toDouble();
        }
        if (v is String) {
          final p = double.tryParse(v.trim());
          if (p != null) {
            return p;
          }
        }
      }
    }
    return null;
  }

  /// UTXO 链手续费估算。
  ///
  /// - **BTC**：`gasPrice` 为 **sat/vB**（整数），`fee = ceil(txSize × sat/vB) / 1e8`。
  /// - **DOGE 等**：`gasPrice` 为 **主单位/vB**（小数，如 `0.00017802`），`fee = txSize × rate`。
  static double? computeUtxoFeeCoin({
    required int txSize,
    required WalletBtcFeeQuote quote,
    String level = 'medium',
  }) {
    if (txSize <= 0) {
      return null;
    }
    final rate = switch (level) {
      'slow' || '低' => quote.slowSatPerVbyte,
      'fast' || '高' => quote.fastSatPerVbyte,
      _ => quote.mediumSatPerVbyte,
    };
    final rateD = double.tryParse(rate.toString());
    if (rateD == null || rateD < 0) {
      return null;
    }
    // sat/vB 通常为 ≥1 的整数；DOGE 网关返回主单位/vB 小数（如 0.00017802）。
    if (rateD < 1.0) {
      return txSize * rateD;
    }
    final feeSat = (txSize * rateD).ceil();
    return feeSat / 1e8;
  }
}
