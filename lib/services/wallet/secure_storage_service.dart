import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../models/recent_recipient.dart';
import '../../models/stored_wallet.dart';
import 'apple_secure_storage_options.dart';
import 'chain_rules.dart';
import 'pin_crypto.dart';

class SecureStorageService {
  SecureStorageService();

  static const _kWalletList = 'wallet_list_v1';
  static const _kActiveId = 'active_wallet_id_v1';
  static const _kPinHash = 'pin_hash_v1';
  static const _kPinSalt = 'pin_salt_v1';
  static const _kPinFailCount = 'pin_fail_count_v1';
  static const _kPinLockUntilMs = 'pin_lock_until_ms_v1';
  static const _kPinSessionUnlockAtPrefix = 'pin_session_unlock_at_ms__';

  static const int _kMaxPinFailures = 5;
  static const Duration _kPinLockDuration = Duration(seconds: 30);

  /// iOS：`read`/`write` 的 `iOptions`；macOS：`mOptions` 来自默认构造参数。
  static const IOSOptions _iosOptions = AppleSecureStorageOptions.ios;

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    iOptions: AppleSecureStorageOptions.ios,
    mOptions: AppleSecureStorageOptions.macOs,
  );

  String _mnemonicKey(String id) => 'wallet_mnemonic__$id';
  String _backedUpKey(String id) => 'wallet_backed_up__$id';
  String _hiddenCoinsKey(String id) => 'wallet_hidden_coins__$id';
  String _recentRecipientsKey(String id) => 'wallet_recent_recipients__$id';
  String _pinSessionUnlockAtKey(String walletId) =>
      '$_kPinSessionUnlockAtPrefix$walletId';

  /// 用于“卸载重装后首次启动”场景：Keychain 默认不会随卸载清空，
  /// 因此重装后需要主动清理钱包相关条目，避免旧钱包被恢复出来。
  ///
  /// 注意：只删除本应用钱包模块使用的 key，避免误伤其它 secure storage 用途。
  Future<void> purgeWalletKeysForFreshInstall() async {
    final all = await _storage.readAll(iOptions: _iosOptions);
    if (all.isEmpty) return;

    bool shouldDelete(String key) {
      if (key == _kWalletList ||
          key == _kActiveId ||
          key == _kPinHash ||
          key == _kPinSalt ||
          key == _kPinFailCount ||
          key == _kPinLockUntilMs) {
        return true;
      }
      if (key.startsWith('wallet_mnemonic__')) return true;
      if (key.startsWith('wallet_backed_up__')) return true;
      if (key.startsWith('wallet_hidden_coins__')) return true;
      if (key.startsWith('wallet_recent_recipients__')) return true;
      if (key.startsWith(_kPinSessionUnlockAtPrefix)) return true;
      return false;
    }

    for (final k in all.keys) {
      if (shouldDelete(k)) {
        await _storage.delete(key: k, iOptions: _iosOptions);
      }
    }
  }

  Future<List<StoredWallet>> readWalletList() async {
    final raw = await _storage.read(key: _kWalletList, iOptions: _iosOptions);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => StoredWallet.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> writeWalletList(List<StoredWallet> wallets) async {
    final json = jsonEncode(wallets.map((w) => w.toJson()).toList());
    await _storage.write(key: _kWalletList, value: json, iOptions: _iosOptions);
  }

  Future<String?> getActiveWalletId() =>
      _storage.read(key: _kActiveId, iOptions: _iosOptions);

  Future<void> setActiveWalletId(String id) =>
      _storage.write(key: _kActiveId, value: id, iOptions: _iosOptions);

  Future<void> clearActiveWalletId() =>
      _storage.delete(key: _kActiveId, iOptions: _iosOptions);

  Future<String?> readMnemonicForWallet(String id) =>
      _storage.read(key: _mnemonicKey(id), iOptions: _iosOptions);

  Future<void> writeMnemonicForWallet(String id, String mnemonic) =>
      _storage.write(
        key: _mnemonicKey(id),
        value: mnemonic.trim(),
        iOptions: _iosOptions,
      );

  Future<void> deleteWalletData(String id) async {
    await _storage.delete(key: _mnemonicKey(id), iOptions: _iosOptions);
    await _storage.delete(key: _backedUpKey(id), iOptions: _iosOptions);
    await _storage.delete(key: _hiddenCoinsKey(id), iOptions: _iosOptions);
    await _storage.delete(key: _recentRecipientsKey(id), iOptions: _iosOptions);
  }

  static const int _kMaxRecentRecipients = 40;

  /// 与 `/api/app/wallet/*` 的 `chain` 参数一致；同一链上同一地址去重，新记录置顶。
  Future<void> recordRecentRecipient({
    required String walletId,
    required String chain,
    required String address,
  }) async {
    final c = chain.trim();
    if (c.isEmpty) {
      return;
    }
    var a = address.trim();
    if (a.isEmpty) {
      return;
    }
    final chainNorm = c.toUpperCase();
    final kind = ChainRules.kindFromChainQuery(c);
    a = ChainRules.normalizeAddressForStorage(kind, a);
    // 防止历史/异常数据污染最近列表（尤其是 TRON 被错误 lowercased 之类）。
    if (kind != ChainKind.unknown && !ChainRules.isValidAddress(kind, a)) {
      return;
    }
    var items = <Map<String, dynamic>>[];
    final raw = await _storage.read(
        key: _recentRecipientsKey(walletId), iOptions: _iosOptions);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final e in list) {
          if (e is Map) {
            items.add(Map<String, dynamic>.from(e));
          }
        }
      } catch (_) {}
    }
    items = items
        .where((e) =>
            (e['chain']?.toString() ?? '').toUpperCase() != chainNorm ||
            ChainRules.normalizeAddressForStorage(
                  kind,
                  (e['address']?.toString() ?? ''),
                ) !=
                a)
        .toList();
    final now = DateTime.now().millisecondsSinceEpoch;
    items.insert(0, {'chain': c, 'address': a, 'atMs': now});
    if (items.length > _kMaxRecentRecipients) {
      items = items.sublist(0, _kMaxRecentRecipients);
    }
    final json = jsonEncode(items);
    await _storage.write(
      key: _recentRecipientsKey(walletId),
      value: json,
      iOptions: _iosOptions,
    );
  }

  /// 仅返回 [chainQuery] 与 [RecentRecipient] 的链标识一致时（不区分大小写）的记录，按时间新到旧。
  Future<List<RecentRecipient>> readRecentRecipientsForChain(
    String walletId,
    String chainQuery,
  ) async {
    final want = chainQuery.trim().toUpperCase();
    if (want.isEmpty) {
      return const [];
    }
    final kind = ChainRules.kindFromChainQuery(chainQuery);
    final raw = await _storage.read(
        key: _recentRecipientsKey(walletId), iOptions: _iosOptions);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final out = <RecentRecipient>[];
      final seen = <String>{};
      for (final e in list) {
        if (e is! Map) {
          continue;
        }
        final m = Map<String, dynamic>.from(e);
        if ((m['chain']?.toString() ?? '').toUpperCase() != want) {
          continue;
        }
        final addrRaw = m['address']?.toString() ?? '';
        final addr = ChainRules.normalizeAddressForStorage(kind, addrRaw);
        if (addr.isEmpty) {
          continue;
        }
        if (kind != ChainKind.unknown &&
            !ChainRules.isValidAddress(kind, addr)) {
          // 过滤无效地址（常见于历史把 TRON 地址错误转小写/加 0x 后造成的脏数据）。
          continue;
        }
        if (!seen.add(addr)) {
          continue;
        }
        out.add(
          RecentRecipient(
            address: addr,
            atMs: (m['atMs'] is int)
                ? m['atMs'] as int
                : int.tryParse(m['atMs']?.toString() ?? '') ?? 0,
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<Set<String>> readHiddenCoinIdsForWallet(String id) async {
    final raw =
        await _storage.read(key: _hiddenCoinsKey(id), iOptions: _iosOptions);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => e.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> writeHiddenCoinIdsForWallet(
      String id, Set<String> hidden) async {
    final json = jsonEncode(hidden.toList()..sort());
    await _storage.write(
        key: _hiddenCoinsKey(id), value: json, iOptions: _iosOptions);
  }

  Future<bool> readBackedUpForWallet(String id) async {
    final v = await _storage.read(key: _backedUpKey(id), iOptions: _iosOptions);
    return v == 'true';
  }

  Future<void> writeBackedUpForWallet(String id, bool value) => _storage.write(
        key: _backedUpKey(id),
        value: value.toString(),
        iOptions: _iosOptions,
      );

  Future<bool> hasPin() async {
    final h = await _storage.read(key: _kPinHash, iOptions: _iosOptions);
    return h != null && h.isNotEmpty;
  }

  Future<void> setPin(String pin) async {
    final salt = PinCrypto.randomSalt();
    final hash = PinCrypto.hashPin(pin, salt);
    await _storage.write(key: _kPinSalt, value: salt, iOptions: _iosOptions);
    await _storage.write(key: _kPinHash, value: hash, iOptions: _iosOptions);
    await _storage.write(
        key: _kPinFailCount, value: '0', iOptions: _iosOptions);
    await _storage.write(
        key: _kPinLockUntilMs, value: '0', iOptions: _iosOptions);
  }

  /// 上次成功解锁会话的时间戳（毫秒），按钱包维度存储。
  ///
  /// 用于“30 分钟内免输 PIN”：
  /// - 切后台即上锁
  /// - 回前台时若距上次解锁 <= 30 分钟，则自动恢复解锁态
  Future<int?> readPinSessionUnlockAtMs(String walletId) async {
    final raw = await _storage.read(
      key: _pinSessionUnlockAtKey(walletId),
      iOptions: _iosOptions,
    );
    final v = int.tryParse(raw ?? '');
    return v == null || v <= 0 ? null : v;
  }

  Future<void> writePinSessionUnlockAtMs(String walletId, int atMs) async {
    await _storage.write(
      key: _pinSessionUnlockAtKey(walletId),
      value: atMs.toString(),
      iOptions: _iosOptions,
    );
  }

  Future<int> _lockRemainingSeconds() async {
    final untilRaw =
        await _storage.read(key: _kPinLockUntilMs, iOptions: _iosOptions);
    final until = int.tryParse(untilRaw ?? '0') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final remainMs = until - now;
    if (remainMs <= 0) return 0;
    return (remainMs / 1000).ceil();
  }

  Future<int> _readFailCount() async {
    final raw = await _storage.read(key: _kPinFailCount, iOptions: _iosOptions);
    return int.tryParse(raw ?? '0') ?? 0;
  }

  Future<void> _writeFailCount(int value) => _storage.write(
      key: _kPinFailCount, value: value.toString(), iOptions: _iosOptions);

  Future<void> _setLockFor(Duration d) async {
    final until = DateTime.now().add(d).millisecondsSinceEpoch;
    await _storage.write(
        key: _kPinLockUntilMs, value: until.toString(), iOptions: _iosOptions);
  }

  /// PIN 校验（带输错次数限制与冷却锁定）
  ///
  /// 返回：
  /// - ok=true：成功
  /// - ok=false 且 lockedSeconds>0：已锁定，需等待
  /// - ok=false 且 remainingAttempts>=0：PIN 错误，还剩几次机会
  Future<PinVerifyResult> verifyPin(String pin) async {
    final locked = await _lockRemainingSeconds();
    if (locked > 0) {
      return PinVerifyResult(lockedSeconds: locked);
    }

    final salt = await _storage.read(key: _kPinSalt, iOptions: _iosOptions);
    final hash = await _storage.read(key: _kPinHash, iOptions: _iosOptions);
    if (salt == null || hash == null) {
      return const PinVerifyResult(remainingAttempts: 0);
    }

    final ok = PinCrypto.hashPin(pin, salt) == hash;
    if (ok) {
      await _writeFailCount(0);
      await _storage.write(
          key: _kPinLockUntilMs, value: '0', iOptions: _iosOptions);
      return const PinVerifyResult(ok: true);
    }

    final fails = (await _readFailCount()) + 1;
    await _writeFailCount(fails);
    final remaining = (_kMaxPinFailures - fails).clamp(0, _kMaxPinFailures);
    if (fails >= _kMaxPinFailures) {
      await _setLockFor(_kPinLockDuration);
      return PinVerifyResult(lockedSeconds: _kPinLockDuration.inSeconds);
    }
    return PinVerifyResult(remainingAttempts: remaining);
  }
}

class PinVerifyResult {
  final bool ok;
  final int? lockedSeconds;
  final int? remainingAttempts;

  const PinVerifyResult({
    this.ok = false,
    this.lockedSeconds,
    this.remainingAttempts,
  });
}
