import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../http/logging_http_client.dart';

String _normAddr(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.startsWith('0x')) {
    return s;
  }
  return '0x$s';
}

/// Blockscout / Etherscan 风格 `account` → `txlist` 中的一条原生币转账。
class BlockscoutAccountTx {
  const BlockscoutAccountTx({
    required this.hash,
    required this.from,
    required this.to,
    required this.valueWei,
    required this.timestamp,
    required this.isSuccess,
    this.confirmations,
  });

  final String hash;
  final String from;
  /// 合约创建等场景可能为空串。
  final String to;
  final BigInt valueWei;
  final DateTime timestamp;
  final bool isSuccess;
  /// 区块确认数；缺失或解析失败时为 `null`，UI 中按「已充分确认」处理。
  final int? confirmations;

  bool isOutgoing(String walletHex) =>
      _normAddr(from) == _normAddr(walletHex);
}

/// 从 Blockscout 公开 API 拉取账户交易列表（与 Etherscan `txlist` 兼容）。
class BlockscoutAccountTxService {
  BlockscoutAccountTxService({http.Client? httpClient})
      : _httpClient = httpClient ?? _defaultHttpClient();

  static const Duration _kRequestTimeout = Duration(seconds: 18);

  final http.Client _httpClient;

  static http.Client _defaultHttpClient() {
    final inner = http.Client();
    if (kDebugMode) {
      return LoggingHttpClient(
        inner,
        logName: 'BlockscoutTx',
        maxLogBodyLength: 48000,
      );
    }
    return inner;
  }

  /// [apiRoot] 为 [EvmEnvironment.blockscoutApiRoot] 返回值。
  Future<List<BlockscoutAccountTx>> fetchTxList({
    required String apiRoot,
    required String address,
    int offset = 40,
  }) async {
    final addr = _normAddr(address);
    final base = Uri.parse(apiRoot);
    final uri = base.replace(
      queryParameters: <String, String>{
        'module': 'account',
        'action': 'txlist',
        'address': addr,
        'startblock': '0',
        'endblock': '99999999',
        'page': '1',
        'offset': '$offset',
        'sort': 'desc',
      },
    );

    final res = await _httpClient.get(uri).timeout(_kRequestTimeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('HTTP ${res.statusCode}');
    }

    final decoded = json.decode(utf8.decode(res.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw StateError('响应格式异常');
    }
    final status = decoded['status']?.toString();
    final result = decoded['result'];

    if (result is String) {
      final t = result.toLowerCase();
      if (t.contains('no transactions') ||
          t.contains('no record') ||
          t == '[]') {
        return const [];
      }
      if (status != '1' && status != 'true') {
        throw StateError(decoded['message']?.toString() ?? result);
      }
      return const [];
    }

    if (result is! List) {
      return const [];
    }

    final out = <BlockscoutAccountTx>[];
    for (final e in result) {
      if (e is! Map<String, dynamic>) {
        continue;
      }
      final hash = e['hash']?.toString();
      final from = e['from']?.toString();
      final to = e['to']?.toString() ?? '';
      final valueStr = e['value']?.toString();
      final tsStr = e['timeStamp']?.toString();
      if (hash == null ||
          hash.isEmpty ||
          from == null ||
          from.isEmpty ||
          valueStr == null ||
          tsStr == null) {
        continue;
      }
      BigInt wei;
      try {
        wei = BigInt.parse(valueStr);
      } catch (_) {
        continue;
      }
      final ts = int.tryParse(tsStr);
      if (ts == null) {
        continue;
      }
      final err = e['isError']?.toString() == '1';
      final receiptFail = e['txreceipt_status']?.toString() == '0';
      final conf = int.tryParse(e['confirmations']?.toString() ?? '');
      out.add(
        BlockscoutAccountTx(
          hash: hash,
          from: from,
          to: to,
          valueWei: wei,
          timestamp: DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true)
              .toLocal(),
          isSuccess: !err && !receiptFail,
          confirmations: conf,
        ),
      );
    }
    return out;
  }
}
