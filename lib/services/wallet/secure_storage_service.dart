import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../models/stored_wallet.dart';
import 'pin_crypto.dart';

class SecureStorageService {
  SecureStorageService();

  static const _kWalletList = 'wallet_list_v1';
  static const _kActiveId = 'active_wallet_id_v1';
  static const _kPinHash = 'pin_hash_v1';
  static const _kPinSalt = 'pin_salt_v1';
  static const _kPinFailCount = 'pin_fail_count_v1';
  static const _kPinLockUntilMs = 'pin_lock_until_ms_v1';

  static const int _kMaxPinFailures = 5;
  static const Duration _kPinLockDuration = Duration(seconds: 30);

  static const IOSOptions _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
  );

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String _mnemonicKey(String id) => 'wallet_mnemonic__$id';
  String _backedUpKey(String id) => 'wallet_backed_up__$id';

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

  Future<String?> readMnemonicForWallet(String id) =>
      _storage.read(key: _mnemonicKey(id), iOptions: _iosOptions);

  Future<void> writeMnemonicForWallet(String id, String mnemonic) => _storage.write(
        key: _mnemonicKey(id),
        value: mnemonic.trim(),
        iOptions: _iosOptions,
      );

  Future<void> deleteWalletData(String id) async {
    await _storage.delete(key: _mnemonicKey(id), iOptions: _iosOptions);
    await _storage.delete(key: _backedUpKey(id), iOptions: _iosOptions);
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
    await _storage.write(key: _kPinFailCount, value: '0', iOptions: _iosOptions);
    await _storage.write(key: _kPinLockUntilMs, value: '0', iOptions: _iosOptions);
  }

  Future<int> _lockRemainingSeconds() async {
    final untilRaw = await _storage.read(key: _kPinLockUntilMs, iOptions: _iosOptions);
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

  Future<void> _writeFailCount(int value) =>
      _storage.write(key: _kPinFailCount, value: value.toString(), iOptions: _iosOptions);

  Future<void> _setLockFor(Duration d) async {
    final until = DateTime.now().add(d).millisecondsSinceEpoch;
    await _storage.write(key: _kPinLockUntilMs, value: until.toString(), iOptions: _iosOptions);
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
      await _storage.write(key: _kPinLockUntilMs, value: '0', iOptions: _iosOptions);
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
