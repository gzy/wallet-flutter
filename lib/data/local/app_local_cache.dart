import 'dart:convert';

import 'package:drift/drift.dart';

import '../../models/app_chain_config.dart';
import '../../models/chain_transaction_vo.dart';
import '../../models/coin_data.dart';
import '../../services/market/app_price_service.dart';
import '../../services/wallet/chain_rules.dart';
import 'app_database.dart';

const _kChainList = 'cache_chains_v1';
const _kPriceAll = 'cache_prices_v1';
String _kEvmCoinsForWallet(String walletId) => 'evm_coins__$walletId';
String _kDerivedAddressesForWallet(String walletId) =>
    'derived_addrs_v1__$walletId';

/// 各链展示/查余额用地址快照（无私钥），用于冷启动在助记词派生完成前先拉余额。
class DerivedAddressSnapshot {
  const DerivedAddressSnapshot({
    required this.addressHex,
    this.tronAddress,
    this.solanaAddress,
    this.xrpAddress,
    this.tonAddressMain,
    this.tonAddressTest,
    this.btcMainnetAddress,
    this.btcTestnetAddress,
    this.dogeMainnetAddress,
    this.dogeTestnetAddress,
  });

  final String addressHex;
  final String? tronAddress;
  final String? solanaAddress;
  final String? xrpAddress;
  final String? tonAddressMain;
  final String? tonAddressTest;
  final String? btcMainnetAddress;
  final String? btcTestnetAddress;
  final String? dogeMainnetAddress;
  final String? dogeTestnetAddress;

  Map<String, dynamic> toJson() => {
        'addressHex': addressHex,
        'tronAddress': tronAddress,
        'solanaAddress': solanaAddress,
        'xrpAddress': xrpAddress,
        'tonAddressMain': tonAddressMain,
        'tonAddressTest': tonAddressTest,
        'btcMainnetAddress': btcMainnetAddress,
        'btcTestnetAddress': btcTestnetAddress,
        'dogeMainnetAddress': dogeMainnetAddress,
        'dogeTestnetAddress': dogeTestnetAddress,
      };

  factory DerivedAddressSnapshot.fromJson(Map<String, dynamic> json) {
    return DerivedAddressSnapshot(
      addressHex: json['addressHex']?.toString() ?? '',
      tronAddress: json['tronAddress']?.toString(),
      solanaAddress: json['solanaAddress']?.toString(),
      xrpAddress: json['xrpAddress']?.toString(),
      tonAddressMain: json['tonAddressMain']?.toString(),
      tonAddressTest: json['tonAddressTest']?.toString(),
      btcMainnetAddress: json['btcMainnetAddress']?.toString(),
      btcTestnetAddress: json['btcTestnetAddress']?.toString(),
      dogeMainnetAddress: json['dogeMainnetAddress']?.toString(),
      dogeTestnetAddress: json['dogeTestnetAddress']?.toString(),
    );
  }
}

String normalizeHexAddr(String a) {
  var s = a.trim();
  if (s.isEmpty) {
    return s;
  }
  if (!s.toLowerCase().startsWith('0x')) {
    s = '0x$s';
  }
  return s.toLowerCase();
}

String normalizeScopeAddress(String address, String chainQuery) {
  final kind = ChainRules.kindFromChainQuery(chainQuery);
  return ChainRules.normalizeAddressForStorage(kind, address);
}

/// 非敏感只读数据：链配置、资产快照、行情、交易历史列表。
class AppLocalCache {
  AppLocalCache(this._db);

  final AppDatabase _db;

  static AppLocalCache open() => AppLocalCache(AppDatabase());

  Future<void> close() => _db.close();

  // --- Chains (GET /api/app/chains) ---

  Future<void> putChains(List<AppChainConfig> list) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final json = jsonEncode(list.map((c) => c.toJson()).toList());
    await _db
        .into(_db.cacheEntries)
        .insertOnConflictUpdate(CacheEntriesCompanion(
          key: const Value(_kChainList),
          payload: Value(json),
          updatedAt: Value(now),
        ));
  }

  Future<List<AppChainConfig>?> getChains() async {
    final r = await (_db.select(_db.cacheEntries)
          ..where((e) => e.key.equals(_kChainList)))
        .getSingleOrNull();
    if (r == null) {
      return null;
    }
    return _parseChainList(r.payload);
  }

  List<AppChainConfig>? _parseChainList(String payload) {
    try {
      final list = jsonDecode(payload) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map((m) => AppChainConfig.fromJson(m))
          .toList();
    } catch (_) {
      return null;
    }
  }

  // --- 派生地址快照（按钱包 id，无私钥） ---

  Future<void> putDerivedAddresses(
    String walletId,
    DerivedAddressSnapshot snapshot,
  ) async {
    if (walletId.isEmpty || snapshot.addressHex.trim().isEmpty) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db
        .into(_db.cacheEntries)
        .insertOnConflictUpdate(CacheEntriesCompanion(
          key: Value(_kDerivedAddressesForWallet(walletId)),
          payload: Value(jsonEncode(snapshot.toJson())),
          updatedAt: Value(now),
        ));
  }

  Future<DerivedAddressSnapshot?> getDerivedAddresses(String walletId) async {
    if (walletId.isEmpty) {
      return null;
    }
    final r = await (_db.select(_db.cacheEntries)
          ..where((e) => e.key.equals(_kDerivedAddressesForWallet(walletId))))
        .getSingleOrNull();
    if (r == null) {
      return null;
    }
    try {
      final m = jsonDecode(r.payload) as Map<String, dynamic>;
      final snap = DerivedAddressSnapshot.fromJson(m);
      if (snap.addressHex.trim().isEmpty) {
        return null;
      }
      return snap;
    } catch (_) {
      return null;
    }
  }

  // --- 行情 (POST /api/app/price/all) ---

  Future<void> putPriceQuotes(Map<String, AppSymbolQuote> quotes) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final m = {
      for (final e in quotes.entries)
        e.key: {
          'price': e.value.price,
          'c': e.value.change24h,
        }
    };
    final json = jsonEncode(m);
    await _db
        .into(_db.cacheEntries)
        .insertOnConflictUpdate(CacheEntriesCompanion(
          key: const Value(_kPriceAll),
          payload: Value(json),
          updatedAt: Value(now),
        ));
  }

  Future<Map<String, AppSymbolQuote>?> getPriceQuotes() async {
    final r = await (_db.select(_db.cacheEntries)
          ..where((e) => e.key.equals(_kPriceAll)))
        .getSingleOrNull();
    if (r == null) {
      return null;
    }
    try {
      final o = jsonDecode(r.payload) as Map<String, dynamic>;
      final out = <String, AppSymbolQuote>{};
      o.forEach((k, v) {
        if (v is! Map) {
          return;
        }
        final m = Map<String, dynamic>.from(v);
        final p = m['price'];
        final c = m['c'];
        out[k] = AppSymbolQuote(
          price: (p is num)
              ? p.toDouble()
              : (double.tryParse(p?.toString() ?? '0') ?? 0),
          change24h: (c is num)
              ? c.toDouble()
              : (double.tryParse(c?.toString() ?? '0') ?? 0),
        );
      });
      return out;
    } catch (_) {
      return null;
    }
  }

  // --- 首页多链资产行（[CoinData] 快照，按当前钱包 id） ---

  Future<void> putEvmCoinsForWallet(
      String walletId, List<CoinData> coins) async {
    if (walletId.isEmpty) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final json = jsonEncode(coins.map((c) => c.toJson()).toList());
    final key = _kEvmCoinsForWallet(walletId);
    await _db
        .into(_db.cacheEntries)
        .insertOnConflictUpdate(CacheEntriesCompanion(
          key: Value(key),
          payload: Value(json),
          updatedAt: Value(now),
        ));
  }

  Future<List<CoinData>?> getEvmCoinsForWallet(String walletId) async {
    if (walletId.isEmpty) {
      return null;
    }
    final key = _kEvmCoinsForWallet(walletId);
    final r = await (_db.select(_db.cacheEntries)
          ..where((e) => e.key.equals(key)))
        .getSingleOrNull();
    if (r == null) {
      return null;
    }
    try {
      final list = jsonDecode(r.payload) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map((m) => CoinData.fromJson(m))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> clearEvmCoinsForWallet(String walletId) async {
    if (walletId.isEmpty) {
      return;
    }
    await (_db.delete(_db.cacheEntries)
          ..where((e) => e.key.equals(_kEvmCoinsForWallet(walletId))))
        .go();
  }

  // --- 交易历史（按 地址+链+币 分桶，与 [WalletTransactionService] 查询键一致） ---

  String transactionScopeKey(
    String address,
    String chain,
    String coinSymbol,
  ) {
    return '${normalizeScopeAddress(address, chain)}|${chain.trim().toUpperCase()}|${coinSymbol.toUpperCase()}';
  }

  String _txMetaKey(String scope) => 'tx_meta__$scope';

  /// 转账成功后丢弃该 scope 的列表缓存，避免详情页先展示旧列表再等待接口。
  Future<void> clearTransactionHistory(String scope) async {
    await _db.batch((b) {
      b.deleteWhere(
        _db.cachedTxs,
        (t) => t.scopeKey.equals(scope),
      );
      b.deleteWhere(
        _db.cacheEntries,
        (e) => e.key.equals(_txMetaKey(scope)),
      );
    });
  }

  Future<void> replaceTransactionHistory(
    String scope,
    List<ChainTransactionVo> list,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.batch((b) {
      b.deleteWhere(
        _db.cachedTxs,
        (t) => t.scopeKey.equals(scope),
      );
      for (var i = 0; i < list.length; i++) {
        final tx = list[i];
        var hash = (tx.txHash?.trim() ?? '');
        if (hash.isEmpty) {
          hash = 'no_hash_$i';
        }
        b.insert(
          _db.cachedTxs,
          CachedTxsCompanion.insert(
            scopeKey: scope,
            txHash: hash,
            payloadJson: jsonEncode(tx.toJson()),
            sortTimeMs: Value(tx.transactionTime?.millisecondsSinceEpoch),
          ),
        );
      }
    });
    await _db
        .into(_db.cacheEntries)
        .insertOnConflictUpdate(CacheEntriesCompanion(
          key: Value(_txMetaKey(scope)),
          payload: const Value('1'),
          updatedAt: Value(now),
        ));
  }

  /// 从未写入过该 scope 时返回 `null`；已写入过（含空列表）时返回可解析的列表（可能为 `[]`）。
  ///
  /// 排序在内存中完成，避免对可空 [CachedTxs.sortTimeMs] 的 SQL `ORDER BY` 在部分环境下异常，
  /// 并逐条解析，单条坏数据不整表丢弃。
  Future<List<ChainTransactionVo>?> getTransactionHistory(String scope) async {
    final meta = await (_db.select(_db.cacheEntries)
          ..where((e) => e.key.equals(_txMetaKey(scope))))
        .getSingleOrNull();
    if (meta == null) {
      return null;
    }
    final rows = await (_db.select(_db.cachedTxs)
          ..where((t) => t.scopeKey.equals(scope)))
        .get();
    // 新到旧，时间缺失的排在后
    rows.sort((a, b) {
      final ta = a.sortTimeMs ?? 0;
      final tb = b.sortTimeMs ?? 0;
      if (ta != tb) {
        return tb.compareTo(ta);
      }
      return b.txHash.compareTo(a.txHash);
    });
    final out = <ChainTransactionVo>[];
    for (final r in rows) {
      try {
        out.add(ChainTransactionVo.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(r.payloadJson) as Map,
          ),
        ));
      } catch (_, __) {
        continue;
      }
    }
    return out;
  }

  // --- 后台模式浮窗开关（按模块 id 持久化） ---

  static String backendFloatEnabledKey(String moduleId) =>
      'backend_float_enabled__${moduleId.trim()}';

  Future<void> putBackendFloatEnabled(String moduleId, bool enabled) async {
    final id = moduleId.trim();
    if (id.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db
        .into(_db.cacheEntries)
        .insertOnConflictUpdate(CacheEntriesCompanion(
          key: Value(backendFloatEnabledKey(id)),
          payload: Value(enabled ? '1' : '0'),
          updatedAt: Value(now),
        ));
  }

  /// `null` 表示从未保存过（调用方可用默认值，一般为启用浮窗）。
  Future<bool?> getBackendFloatEnabled(String moduleId) async {
    final id = moduleId.trim();
    if (id.isEmpty) return null;
    final r = await (_db.select(_db.cacheEntries)
          ..where((e) => e.key.equals(backendFloatEnabledKey(id))))
        .getSingleOrNull();
    if (r == null) return null;
    return r.payload == '1';
  }
}
