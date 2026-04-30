import 'package:flutter/foundation.dart';

import 'tron_utils.dart';

enum ChainKind {
  evm,
  tron,
  unknown,
}

class ChainRules {
  ChainRules._();

  static String _stripTron0xPrefix(String s) {
    final t = s.trim();
    if (t.length >= 3 &&
        (t.startsWith('0x') || t.startsWith('0X')) &&
        (t[2] == 'T' || t[2] == 't')) {
      return t.substring(2);
    }
    return t;
  }

  static ChainKind kindFromChainType(String? chainType) {
    final t = (chainType ?? '').trim().toUpperCase();
    if (t.isEmpty) return ChainKind.unknown;
    if (t == 'TRON') return ChainKind.tron;
    if (t == 'EVM') return ChainKind.evm;
    return ChainKind.unknown;
  }

  static ChainKind kindFromChainQuery(String? chainQuery) {
    final q = (chainQuery ?? '').trim().toUpperCase();
    if (q.isEmpty) return ChainKind.unknown;
    if (q == 'TRX' ||
        q == 'TRON' ||
        q.startsWith('TRON_') ||
        q.contains('TRON')) {
      return ChainKind.tron;
    }
    // 后端链查询参数常见为 ETH/BSC/...，默认按 EVM 处理。
    return ChainKind.evm;
  }

  static String badgeLabel(ChainKind kind) {
    switch (kind) {
      case ChainKind.tron:
        return 'TRON';
      case ChainKind.evm:
        return 'EVM';
      case ChainKind.unknown:
        return '—';
    }
  }

  /// 用于持久化与去重的“规范化地址”：
  /// - EVM：补 `0x` 并转小写
  /// - TRON：保持原样（Base58Check 大小写敏感）
  static String normalizeAddressForStorage(ChainKind kind, String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    switch (kind) {
      case ChainKind.tron:
        s = _stripTron0xPrefix(s).replaceAll(RegExp(r'\s+'), '');
        return s;
      case ChainKind.evm:
        final x = s.toLowerCase();
        return x.startsWith('0x') ? x : '0x$x';
      case ChainKind.unknown:
        return s;
    }
  }

  /// UI 展示用地址：
  /// - EVM：补 `0x`（不强制改大小写，避免用户感知“被改写”）
  /// - TRON：原样
  static String formatAddressForUi(ChainKind kind, String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    switch (kind) {
      case ChainKind.tron:
        return _stripTron0xPrefix(s).replaceAll(RegExp(r'\s+'), '');
      case ChainKind.evm:
        return s.startsWith('0x') || s.startsWith('0X') ? s : '0x$s';
      case ChainKind.unknown:
        return s;
    }
  }

  static bool isValidAddress(ChainKind kind, String raw) {
    final s = raw.trim();
    if (s.isEmpty) return false;
    switch (kind) {
      case ChainKind.tron:
        return isValidTronAddress(_stripTron0xPrefix(s));
      case ChainKind.evm:
        final x = s.startsWith('0x') || s.startsWith('0X') ? s : '0x$s';
        return RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(x);
      case ChainKind.unknown:
        if (kDebugMode) {
          debugPrint('ChainRules.isValidAddress: unknown kind for "$s"');
        }
        return false;
    }
  }
}
