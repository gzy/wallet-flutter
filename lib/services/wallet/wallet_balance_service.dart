import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../http/http_clients.dart';
import 'wallet_api_paths.dart';

/// 与 OpenAPI `GET /api/app/wallet/balance`（`WalletBalanceVO`）一致的单条余额。
class WalletBalanceEntry {
  const WalletBalanceEntry({
    required this.balance,
    this.chain,
    this.crypto,
    this.protocol,
  });

  final double balance;
  final String? chain;
  final String? crypto;
  final String? protocol;

  factory WalletBalanceEntry.fromJson(Map<String, dynamic> json) {
    return WalletBalanceEntry(
      balance: (json['balance'] as num?)?.toDouble() ?? 0,
      chain: json['chain']?.toString(),
      crypto: json['crypto']?.toString(),
      protocol: json['protocol']?.toString(),
    );
  }
}

/// 批量余额请求项（OpenAPI `BatchWalletBalanceDTO.items[]`）。
class BatchBalanceRequestItem {
  const BatchBalanceRequestItem({
    required this.address,
    required this.chain,
    this.coin,
  });

  final String address;
  final String chain;
  final String? coin;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'address': address,
      'chain': chain,
    };
    final c = coin?.trim();
    if (c != null && c.isNotEmpty) {
      m['coin'] = c;
    }
    return m;
  }
}

/// 批量余额响应单项（OpenAPI `BatchWalletBalanceVO`）。
class BatchWalletBalanceResult {
  const BatchWalletBalanceResult({
    this.address,
    this.chain,
    this.coin,
    this.success = false,
    this.balances = const [],
    this.errorMessage,
  });

  final String? address;
  final String? chain;
  final String? coin;
  final bool success;
  final List<WalletBalanceEntry> balances;
  final String? errorMessage;

  factory BatchWalletBalanceResult.fromJson(Map<String, dynamic> json) {
    final raw = json['balances'];
    final list = <WalletBalanceEntry>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          list.add(
            WalletBalanceEntry.fromJson(Map<String, dynamic>.from(e)),
          );
        }
      }
    }
    return BatchWalletBalanceResult(
      address: json['address']?.toString(),
      chain: json['chain']?.toString(),
      coin: json['coin']?.toString(),
      success: json['success'] == true,
      balances: list,
      errorMessage: json['errorMessage']?.toString(),
    );
  }
}

/// 后端聚合余额（与链上 RPC 二选一由 [WalletController] 决定）。
///
/// - 单链：`GET /api/app/wallet/balance`
/// - 首页等多链：`POST /api/app/wallet/balances/batch`
class WalletBalanceService {
  WalletBalanceService({http.Client? httpClient})
      : _httpClient = httpClient ?? _defaultClient();

  final http.Client _httpClient;

  static http.Client _defaultClient() {
    return HttpClients.create(
        logName: 'WalletBalance', maxLogBodyLength: 12000);
  }

  static bool _looksLikeStaleSocketOrTls(Object e) {
    final s = e.toString().toUpperCase();
    return s.contains('WRONG_VERSION_NUMBER') ||
        s.contains('HANDSHAKE') ||
        s.contains('TLSV1_ALERT') ||
        s.contains('CONNECTION RESET') ||
        s.contains('BROKEN PIPE') ||
        s.contains('SOCKET_EXCEPTION');
  }

  static const int _batchMaxItems = 50;

  /// `POST /api/app/wallet/balances/batch`；成功且 `code == 0` 时返回结果列表。
  /// 超过 50 项时自动分片请求并合并（OpenAPI `maxItems: 50`）。
  Future<List<BatchWalletBalanceResult>?> fetchBalancesBatch({
    required List<BatchBalanceRequestItem> items,
  }) async {
    if (items.isEmpty) {
      return [];
    }
    final merged = <BatchWalletBalanceResult>[];
    for (var i = 0; i < items.length; i += _batchMaxItems) {
      final end = i + _batchMaxItems > items.length
          ? items.length
          : i + _batchMaxItems;
      final chunk = items.sublist(i, end);
      final part = await _fetchBalancesBatchChunk(chunk);
      if (part == null) {
        return null;
      }
      merged.addAll(part);
    }
    return merged;
  }

  Future<List<BatchWalletBalanceResult>?> _fetchBalancesBatchChunk(
    List<BatchBalanceRequestItem> items,
  ) async {
    final uri = WalletApiPaths.balancesBatchUri();
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
              body: jsonEncode({
                'items': items.map((e) => e.toJson()).toList(),
              }),
            )
            .timeout(const Duration(seconds: 45));

        if (res.statusCode < 200 || res.statusCode >= 300) {
          if (kDebugMode) {
            debugPrint(
              'WalletBalanceService.fetchBalancesBatch: HTTP ${res.statusCode}',
            );
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
              'WalletBalanceService.fetchBalancesBatch: '
              'code=${decoded['code']} msg=${decoded['message']}',
            );
          }
          return null;
        }

        final data = decoded['data'];
        if (data is! List) {
          return [];
        }

        return data
            .whereType<Map>()
            .map(
              (e) => BatchWalletBalanceResult.fromJson(
                Map<String, dynamic>.from(e),
              ),
            )
            .toList();
      } catch (e, st) {
        final retryable = attempt < maxAttempts - 1 &&
            (e is SocketException ||
                e is HandshakeException ||
                e is TlsException ||
                _looksLikeStaleSocketOrTls(e));
        if (retryable) {
          if (kDebugMode) {
            debugPrint(
              'WalletBalanceService.fetchBalancesBatch: retry ${attempt + 1} after $e',
            );
          }
          await Future<void>.delayed(
            Duration(milliseconds: 120 * (attempt + 1)),
          );
          continue;
        }
        debugPrint('WalletBalanceService.fetchBalancesBatch: $e\n$st');
        return null;
      }
    }
    return null;
  }

  /// 成功且 `code == 0` 时返回 `data` 列表（可能为空）；HTTP/解析/`code != 0` 时返回 `null`。
  Future<List<WalletBalanceEntry>?> fetchBalances({
    required String address,
    required String chain,
    String? coin,
  }) async {
    final uri = WalletApiPaths.balance(
      address: address,
      chain: chain,
      coin: coin,
    );
    const maxAttempts = 3;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final headers = <String, String>{
          'Accept': '*/*',
          if (attempt > 0) 'connection': 'close',
        };
        final res =
            await _httpClient.get(uri, headers: headers).timeout(
                  const Duration(seconds: 20),
                );

        if (res.statusCode < 200 || res.statusCode >= 300) {
          if (kDebugMode) {
            debugPrint('WalletBalanceService: HTTP ${res.statusCode}');
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
              'WalletBalanceService: code=${decoded['code']} msg=${decoded['message']}',
            );
          }
          return null;
        }

        final data = decoded['data'];
        if (data is! List) {
          return [];
        }

        return data
            .whereType<Map>()
            .map((e) =>
                WalletBalanceEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (e, st) {
        final retryable = attempt < maxAttempts - 1 &&
            (e is SocketException ||
                e is HandshakeException ||
                e is TlsException ||
                _looksLikeStaleSocketOrTls(e));
        if (retryable) {
          if (kDebugMode) {
            debugPrint(
              'WalletBalanceService.fetchBalances: retry ${attempt + 1} after $e',
            );
          }
          await Future<void>.delayed(
            Duration(milliseconds: 120 * (attempt + 1)),
          );
          continue;
        }
        debugPrint('WalletBalanceService.fetchBalances: $e\n$st');
        return null;
      }
    }
    return null;
  }
}
