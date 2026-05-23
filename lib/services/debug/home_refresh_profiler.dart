import 'package:flutter/foundation.dart';

/// 首页冷启动 / 下拉刷新时各接口耗时（仅 debug 输出）。
class HomeRefreshProfiler {
  HomeRefreshProfiler._();

  static final Stopwatch _sw = Stopwatch();
  static bool _active = false;

  static void begin(String scope) {
    if (!kDebugMode) return;
    _active = true;
    _sw
      ..reset()
      ..start();
    debugPrint('[HomeRefresh][$scope] --- start ---');
  }

  static void mark(String label) {
    if (!kDebugMode || !_active) return;
    debugPrint('[HomeRefresh] +${_sw.elapsedMilliseconds}ms $label');
  }

  static void end(String scope) {
    if (!kDebugMode || !_active) return;
    debugPrint('[HomeRefresh][$scope] total ${_sw.elapsedMilliseconds}ms');
    _active = false;
    _sw.stop();
  }

  /// `POST /api/app/price/all` 耗时（仅 debug）。
  static void logPriceFetchDone({
    required int wallMs,
    required int pairCount,
    bool usedCacheFallback = false,
    bool requestFailed = false,
  }) {
    if (!kDebugMode) return;
    final cacheNote = usedCacheFallback ? ', Drift cache fallback' : '';
    final failNote = requestFailed ? ', request failed/empty' : '';
    debugPrint(
      '[HomeRefresh] POST /api/app/price/all: $pairCount pair(s) in ${wallMs}ms '
      '(含 JSON 解析；分段耗时见 [AppPrice] … 签名 · 网络 · 读体)'
      '$cacheNote$failNote',
    );
  }

  /// 余额批次结束汇总（仅 debug）：`mode` 为 `POST balances/batch` 或 `per-chain GET`。
  static void logBalanceBatchDone({
    required int wallMs,
    required int chainCount,
    required Map<String, int> perChainMs,
    String mode = 'balance',
    int? balanceRowCount,
  }) {
    if (!kDebugMode) return;
    if (perChainMs.isEmpty) {
      debugPrint(
        '[HomeRefresh] $mode: ${wallMs}ms (0 chains, no requests)',
      );
      return;
    }
    final sorted = perChainMs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sumMs = sorted.fold<int>(0, (n, e) => n + e.value);
    final slow = sorted.first;
    final rowsSuffix = balanceRowCount != null
        ? ', $balanceRowCount balance row(s) in response'
        : '';
    final buf = StringBuffer(
      '[HomeRefresh] $mode: $chainCount chain(s) in ${wallMs}ms$rowsSuffix '
      '(含 JSON 解析；分段耗时见 [WalletBalance] … 签名 · 网络 · 读体)\n',
    );
    if (sorted.length == 1) {
      buf.write('  (single request wall time)\n');
    } else {
      buf.write(
        '  (parallel wall; per-chain sum ${sumMs}ms)\n',
      );
      buf.write('  slowest: ${slow.key} ${slow.value}ms\n');
      for (final e in sorted) {
        buf.write('  - ${e.key}: ${e.value}ms\n');
      }
    }
    debugPrint(buf.toString().trimRight());
  }
}
