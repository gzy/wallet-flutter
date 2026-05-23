import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:bs58/bs58.dart' as bs58;
import 'package:flutter/foundation.dart';
import 'package:ton_dart/ton_dart.dart';

import '../../models/app_chain_config.dart';
import 'tron_utils.dart';
import 'xrp_utils.dart';

enum ChainKind {
  evm,
  tron,
  solana,
  xrp,
  btc,
  doge,
  ton,
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

  static bool _isDogeChainQuery(String q) {
    final u = q.trim().toUpperCase();
    return u == 'DOGE' || u == 'DOG' || u == 'DOGECOIN';
  }

  static ChainKind kindFromChainType(String? chainType, {String? chainQuery}) {
    final t = (chainType ?? '').trim().toUpperCase();
    if (t.isEmpty) return ChainKind.unknown;
    if (t == 'TRON') return ChainKind.tron;
    if (t == 'EVM') return ChainKind.evm;
    if (t == 'SOLANA' || t == 'SOL') return ChainKind.solana;
    // 后端部分环境返回 XRPL（XRP Ledger），与 XRP 等价。
    if (t == 'XRP' || t == 'RIPPLE' || t == 'XRPL') return ChainKind.xrp;
    if (t == 'BTC' || t == 'BITCOIN') return ChainKind.btc;
    if (t == 'TON') return ChainKind.ton;
    if (t == 'UTXO' && _isDogeChainQuery(chainQuery ?? '')) {
      return ChainKind.doge;
    }
    return ChainKind.unknown;
  }

  static ChainKind kindFromChainQuery(String? chainQuery) {
    final q = (chainQuery ?? '').trim().toUpperCase();
    if (q.isEmpty) return ChainKind.unknown;
    if (q == 'TON') {
      return ChainKind.ton;
    }
    if (q == 'BTC' || q == 'BITCOIN') {
      return ChainKind.btc;
    }
    if (_isDogeChainQuery(q)) {
      return ChainKind.doge;
    }
    if (q == 'SOL' || q == 'SOLANA') {
      return ChainKind.solana;
    }
    if (q == 'XRP' || q == 'RIPPLE' || q == 'XRPL') {
      return ChainKind.xrp;
    }
    if (q == 'TRX' ||
        q == 'TRON' ||
        q.startsWith('TRON_') ||
        q.contains('TRON')) {
      return ChainKind.tron;
    }
    // 后端链查询参数常见为 ETH/BSC/...，默认按 EVM 处理（BTC 已在上方显式识别）。
    return ChainKind.evm;
  }

  /// 网络选择、收款等：优先 [chainType]，未知时按 `chain` 查询参数推断（如 SOL 无 chainType）。
  static ChainKind kindForAppChain(AppChainConfig cfg) {
    final q = cfg.walletApiChainQuery;
    final fromType = kindFromChainType(cfg.chainType, chainQuery: q);
    if (fromType != ChainKind.unknown) {
      return fromType;
    }
    return kindFromChainQuery(q);
  }

  static String badgeLabel(ChainKind kind) {
    switch (kind) {
      case ChainKind.tron:
        return 'TRON';
      case ChainKind.evm:
        return 'EVM';
      case ChainKind.solana:
        return 'SOL';
      case ChainKind.xrp:
        return 'XRP';
      case ChainKind.btc:
        return 'BTC';
      case ChainKind.doge:
        return 'DOGE';
      case ChainKind.ton:
        return 'TON';
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
      case ChainKind.solana:
        return s.replaceAll(RegExp(r'\s+'), '');
      case ChainKind.xrp:
        return _stripTron0xPrefix(s).replaceAll(RegExp(r'\s+'), '');
      case ChainKind.btc:
        return s.replaceAll(RegExp(r'\s+'), '').toLowerCase();
      case ChainKind.doge:
        return s.replaceAll(RegExp(r'\s+'), '');
      case ChainKind.ton:
        return _normalizeTonAddressForStorage(s);
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
      case ChainKind.solana:
        return s.replaceAll(RegExp(r'\s+'), '');
      case ChainKind.xrp:
        return _stripTron0xPrefix(s).replaceAll(RegExp(r'\s+'), '');
      case ChainKind.btc:
        return s.replaceAll(RegExp(r'\s+'), '');
      case ChainKind.doge:
        return s.replaceAll(RegExp(r'\s+'), '');
      case ChainKind.ton:
        return _formatTonAddressForUi(s);
      case ChainKind.unknown:
        return s;
    }
  }

  static String _normalizeTonAddressForStorage(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    try {
      return TonAddress(t).toFriendlyAddress(urlSafe: true);
    } catch (_) {
      return t.replaceAll(RegExp(r'\s+'), '');
    }
  }

  static String _formatTonAddressForUi(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    try {
      return TonAddress(t).toFriendlyAddress(urlSafe: true);
    } catch (_) {
      return t.replaceAll(RegExp(r'\s+'), '');
    }
  }

  static bool _isValidSolanaAddress(String raw) {
    try {
      final d = bs58.base58.decode(raw.trim());
      return d.length == 32;
    } catch (_) {
      return false;
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
      case ChainKind.solana:
        return _isValidSolanaAddress(s);
      case ChainKind.xrp:
        return isValidXrpClassicAddress(s);
      case ChainKind.btc:
        return _isValidBtcSegwitAddress(s);
      case ChainKind.doge:
        return _isValidDogeP2pkhAddress(s);
      case ChainKind.ton:
        return _isValidTonAddress(s);
      case ChainKind.unknown:
        if (kDebugMode) {
          debugPrint('ChainRules.isValidAddress: unknown kind for "$s"');
        }
        return false;
    }
  }

  /// TON 友好地址（Base64url）或 raw `workchain:hex`。
  static bool _isValidTonAddress(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    try {
      TonAddress(t);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 主网 / 测试网 Native SegWit（bc1… / tb1…）；用库解析校验 bech32。
  static bool _isValidBtcSegwitAddress(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    final lower = t.toLowerCase();
    try {
      if (lower.startsWith('tb1')) {
        P2wpkhAddress.fromAddress(
          address: t,
          network: BitcoinNetwork.testnet,
        );
        return true;
      }
      if (lower.startsWith('bc1')) {
        P2wpkhAddress.fromAddress(
          address: t,
          network: BitcoinNetwork.mainnet,
        );
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Dogecoin P2PKH：主网 `D…`，测试网 `n…` / `m…`（由库解析校验）。
  static bool _isValidDogeP2pkhAddress(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    try {
      if (t.startsWith('D')) {
        DogeAddress(t, network: DogecoinNetwork.mainnet);
        return true;
      }
      DogeAddress(t, network: DogecoinNetwork.testnet);
      return true;
    } catch (_) {
      return false;
    }
  }
}
