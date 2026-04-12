import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web3dart/web3dart.dart';

import '../models/coin_data.dart';
import '../models/evm_network.dart';
import '../models/stored_wallet.dart';
import '../config/evm_environment.dart';
import '../services/evm/evm_client.dart';
import '../services/evm/send_service.dart';
import '../services/evm/token_service.dart';
import '../services/market/app_price_service.dart';
import '../services/wallet/hd_wallet_service.dart';
import '../services/wallet/mnemonic_service.dart';
import '../services/wallet/secure_storage_service.dart';

/// 全局钱包状态：多钱包、PIN、助记词派生、EVM 余额、发送交易
class WalletController extends ChangeNotifier {
  WalletController({
    SecureStorageService? storage,
    TokenService? tokenService,
    SendService? sendService,
    AppPriceService? appPriceService,
  })  : _storage = storage ?? SecureStorageService(),
        _tokenService = tokenService ?? TokenService(),
        _sendService = sendService ?? SendService(),
        _appPriceService = appPriceService ?? AppPriceService();

  final SecureStorageService _storage;
  final TokenService _tokenService;
  final SendService _sendService;
  final AppPriceService _appPriceService;

  static const _uuid = Uuid();

  List<StoredWallet> _wallets = [];
  String? _activeWalletId;
  EthPrivateKey? _credentials;
  String? _addressHex;
  bool _backedUp = false;
  bool _loading = false;
  EvmNetworkId _sendNetwork = EvmNetworkId.ethereum;
  bool _pinEnabled = false;
  bool _sessionUnlocked = true;
  bool _initReady = false;

  List<CoinData> _evmCoins = [];

  bool get hasWallet => _credentials != null;
  String? get addressHex => _addressHex;
  EthereumAddress? get address =>
      _addressHex == null ? null : EthereumAddress.fromHex(_addressHex!);
  bool get backedUp => _backedUp;
  bool get loading => _loading;
  EvmNetworkId get sendNetwork => _sendNetwork;
  List<CoinData> get evmCoins => List.unmodifiable(_evmCoins);

  List<StoredWallet> get wallets => List.unmodifiable(_wallets);
  String? get activeWalletId => _activeWalletId;
  StoredWallet? get activeWallet {
    for (final w in _wallets) {
      if (w.id == _activeWalletId) {
        return w;
      }
    }
    return null;
  }

  bool get pinEnabled => _pinEnabled;
  bool get sessionUnlocked => _sessionUnlocked;
  bool get initReady => _initReady;

  void setSendNetwork(EvmNetworkId id) {
    _sendNetwork = id;
    notifyListeners();
  }

  Future<void> init() async {
    _initReady = false;
    notifyListeners();
    try {
      _pinEnabled = await _storage.hasPin();
      _wallets = await _storage.readWalletList();
      await _reconcileBackedUpFromLegacyKeys();
      _activeWalletId = await _storage.getActiveWalletId();
      if (_activeWalletId == null && _wallets.isNotEmpty) {
        _activeWalletId = _wallets.first.id;
        await _storage.setActiveWalletId(_activeWalletId!);
      }
      if (_pinEnabled) {
        _sessionUnlocked = false;
      } else {
        _sessionUnlocked = true;
      }
      await _loadCredentialsFromActiveMnemonic();
    } catch (e, st) {
      debugPrint('WalletController.init failed: $e\n$st');
    } finally {
      _initReady = true;
      notifyListeners();
    }
    if (_credentials != null) {
      unawaited(refreshBalances());
    }
  }

  /// 历史版本 [markBackedUp] 只写了 `wallet_backed_up__` 未写钱包列表 JSON，重启后列表里仍为未备份。
  /// 启动时若独立 key 为已备份则合并进列表并持久化。
  Future<void> _reconcileBackedUpFromLegacyKeys() async {
    var dirty = false;
    final next = <StoredWallet>[];
    for (final w in _wallets) {
      if (!w.backedUp && await _storage.readBackedUpForWallet(w.id)) {
        next.add(w.copyWith(backedUp: true));
        dirty = true;
      } else {
        next.add(w);
      }
    }
    if (dirty) {
      _wallets = next;
      await _storage.writeWalletList(_wallets);
    }
  }

  Future<void> _loadCredentialsFromActiveMnemonic() async {
    _credentials = null;
    _addressHex = null;
    _backedUp = false;
    final id = _activeWalletId;
    if (id == null) {
      return;
    }
    final m = await _storage.readMnemonicForWallet(id);
    if (m == null || m.isEmpty) {
      return;
    }
    try {
      _credentials = HdWalletService.privateKeyFromMnemonic(m);
      _addressHex = _credentials!.address.hex;
      final idx = _wallets.indexWhere((w) => w.id == id);
      _backedUp = idx >= 0
          ? _wallets[idx].backedUp
          : await _storage.readBackedUpForWallet(id);
    } catch (e, st) {
      debugPrint('Wallet init failed: $e\n$st');
      _credentials = null;
      _addressHex = null;
    }
  }

  /// 创建新钱包；若已设置 PIN 则校验 [pin]，否则写入 PIN。
  Future<void> createWallet(String pin) async {
    if (await _storage.hasPin()) {
      final r = await _storage.verifyPin(pin);
      if (!r.ok) {
        if (r.lockedSeconds != null && r.lockedSeconds! > 0) {
          throw StateError('PIN 已锁定，请 ${r.lockedSeconds}s 后再试');
        }
        throw StateError('PIN 不正确');
      }
    } else {
      await _storage.setPin(pin);
      _pinEnabled = true;
    }

    final m = MnemonicService.generateMnemonic();
    final id = _uuid.v4();
    final name = 'Wallet ${_wallets.length + 1}';

    await _storage.writeMnemonicForWallet(id, m);
    await _storage.writeBackedUpForWallet(id, false);
    final next = [
      ..._wallets,
      StoredWallet(
        id: id,
        name: name,
        backedUp: false,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      )
    ];
    await _storage.writeWalletList(next);
    await _storage.setActiveWalletId(id);

    _wallets = next;
    _activeWalletId = id;
    _credentials = HdWalletService.privateKeyFromMnemonic(m);
    _addressHex = _credentials!.address.hex;
    _backedUp = false;
    _sessionUnlocked = true;
    await refreshBalances();
    notifyListeners();
  }

  /// 若 [mnemonic] 规范化后与某已存钱包相同则返回该钱包，否则 `null`（助记词无效时亦返回 `null`）。
  Future<StoredWallet?> findWalletWithSameMnemonic(String mnemonic) async {
    final phrase = mnemonic.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (!MnemonicService.validateMnemonic(phrase)) {
      return null;
    }
    final target = MnemonicService.normalizeForCompare(phrase);
    for (final w in _wallets) {
      final existing = await _storage.readMnemonicForWallet(w.id);
      if (existing == null || existing.isEmpty) {
        continue;
      }
      if (!MnemonicService.validateMnemonic(existing)) {
        continue;
      }
      if (MnemonicService.normalizeForCompare(existing) == target) {
        return w;
      }
    }
    return null;
  }

  /// 导入助记词钱包
  Future<void> importWallet(String mnemonic, String pin) async {
    final phrase = mnemonic.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (!MnemonicService.validateMnemonic(phrase)) {
      throw StateError('助记词无效');
    }
    final duplicate = await findWalletWithSameMnemonic(phrase);
    if (duplicate != null) {
      throw StateError('该助记词已在钱包「${duplicate.name}」中使用，无需重复导入');
    }
    if (await _storage.hasPin()) {
      final r = await _storage.verifyPin(pin);
      if (!r.ok) {
        if (r.lockedSeconds != null && r.lockedSeconds! > 0) {
          throw StateError('PIN 已锁定，请 ${r.lockedSeconds}s 后再试');
        }
        throw StateError('PIN 不正确');
      }
    } else {
      await _storage.setPin(pin);
      _pinEnabled = true;
    }

    final id = _uuid.v4();
    final name = 'Wallet ${_wallets.length + 1}';
    await _storage.writeMnemonicForWallet(id, phrase);
    await _storage.writeBackedUpForWallet(id, false);
    final next = [
      ..._wallets,
      StoredWallet(
        id: id,
        name: name,
        backedUp: false,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      )
    ];
    await _storage.writeWalletList(next);
    await _storage.setActiveWalletId(id);

    _wallets = next;
    _activeWalletId = id;
    _credentials = HdWalletService.privateKeyFromMnemonic(phrase);
    _addressHex = _credentials!.address.hex;
    _backedUp = false;
    _sessionUnlocked = true;
    await refreshBalances();
    notifyListeners();
  }

  Future<void> switchWallet(String id) async {
    if (!_wallets.any((w) => w.id == id)) {
      return;
    }
    await _storage.setActiveWalletId(id);
    _activeWalletId = id;
    await _loadCredentialsFromActiveMnemonic();
    if (_credentials != null) {
      await refreshBalances();
    } else {
      notifyListeners();
    }
  }

  Future<void> renameActiveWallet(String name) async {
    final id = _activeWalletId;
    if (id == null) {
      return;
    }
    await renameWallet(id, name);
  }

  Future<void> renameWallet(String walletId, String name) async {
    if (!_wallets.any((w) => w.id == walletId)) {
      return;
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _wallets = _wallets
        .map((w) => w.id == walletId ? w.copyWith(name: trimmed) : w)
        .toList();
    await _storage.writeWalletList(_wallets);
    notifyListeners();
  }

  /// 删除钱包及其助记词；若删的是当前钱包则自动切换到列表中的第一个（若有）。
  Future<void> deleteWallet(String id) async {
    if (!_wallets.any((w) => w.id == id)) {
      return;
    }
    await _storage.deleteWalletData(id);
    final next = _wallets.where((w) => w.id != id).toList();
    await _storage.writeWalletList(next);
    _wallets = next;

    if (_activeWalletId == id) {
      if (next.isEmpty) {
        _activeWalletId = null;
        await _storage.clearActiveWalletId();
        _credentials = null;
        _addressHex = null;
        _backedUp = false;
        _evmCoins = [];
      } else {
        _activeWalletId = next.first.id;
        await _storage.setActiveWalletId(_activeWalletId!);
        await _loadCredentialsFromActiveMnemonic();
        if (_credentials != null) {
          await refreshBalances();
        }
      }
    }
    notifyListeners();
  }

  Future<String?> readMnemonicForBackup() async {
    final id = _activeWalletId;
    if (id == null) {
      return null;
    }
    return _storage.readMnemonicForWallet(id);
  }

  /// 根据助记词推导该钱包的 EVM 地址（十六进制，带 0x），不切换当前钱包。
  Future<String?> readAddressHexForWallet(String walletId) async {
    final m = await _storage.readMnemonicForWallet(walletId);
    if (m == null || m.isEmpty) {
      return null;
    }
    try {
      return HdWalletService.privateKeyFromMnemonic(m).address.hex;
    } catch (e, st) {
      debugPrint('readAddressHexForWallet: $e\n$st');
      return null;
    }
  }

  Future<PinVerifyResult> verifyTransactionPin(String pin) =>
      _storage.verifyPin(pin);

  Future<PinVerifyResult> unlockSession(String pin) async {
    final r = await _storage.verifyPin(pin);
    if (r.ok) {
      _sessionUnlocked = true;
      notifyListeners();
    }
    return r;
  }

  void lockSession() {
    if (_pinEnabled) {
      _sessionUnlocked = false;
      notifyListeners();
    }
  }

  Future<void> markBackedUp() async {
    final id = _activeWalletId;
    if (id == null) {
      return;
    }
    await _storage.writeBackedUpForWallet(id, true);
    _wallets = _wallets
        .map((w) => w.id == id ? w.copyWith(backedUp: true) : w)
        .toList();
    await _storage.writeWalletList(_wallets);
    _backedUp = true;
    notifyListeners();
  }

  Future<void> refreshBalances() async {
    if (_credentials == null) {
      return;
    }
    _loading = true;
    notifyListeners();
    try {
      final addr = _credentials!.address;
      final quotes = await _appPriceService.fetchAllPrices();
      final coins = <CoinData>[];
      for (final cfg in EvmEnvironment.nativeCoins) {
        final bal =
            await _tokenService.getEthBalanceEther(cfg.networkKey, addr);
        final pair = AppPriceService.usdtPairKeyForSymbol(cfg.symbol);
        final q = quotes[pair];
        final price = q?.price ?? 0;
        final change = q?.change24h ?? 0;
        coins.add(
          CoinData(
            id: cfg.coinListId,
            symbol: cfg.symbol,
            name: cfg.name,
            icon: cfg.icon,
            network: cfg.networkLabel,
            chainId: EvmEnvironment.chainId(cfg.networkKey),
            price: price,
            priceChange24h: change,
            balance: bal,
            balanceUSD: bal * price,
          ),
        );
      }
      _evmCoins = coins;
    } catch (e, st) {
      debugPrint('refreshBalances: $e\n$st');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 首页下拉刷新：重读钱包列表与当前选中钱包，并刷新链上余额与行情。
  Future<void> refreshWalletHome() async {
    try {
      _wallets = await _storage.readWalletList();
      await _reconcileBackedUpFromLegacyKeys();
      _activeWalletId = await _storage.getActiveWalletId();
      if (_activeWalletId != null &&
          !_wallets.any((w) => w.id == _activeWalletId)) {
        _activeWalletId = null;
        await _storage.clearActiveWalletId();
      }
      if (_activeWalletId == null && _wallets.isNotEmpty) {
        _activeWalletId = _wallets.first.id;
        await _storage.setActiveWalletId(_activeWalletId!);
      }
      await _loadCredentialsFromActiveMnemonic();
      if (_credentials != null) {
        await refreshBalances();
      } else {
        _evmCoins = [];
        notifyListeners();
      }
    } catch (e, st) {
      debugPrint('refreshWalletHome: $e\n$st');
      notifyListeners();
    }
  }

  Future<String> sendEth({
    required EvmNetworkId network,
    required String toHex,
    required String amountEther,
  }) async {
    final c = _credentials;
    if (c == null) {
      throw StateError('No wallet');
    }
    return _sendService.sendEth(
      network: network,
      credentials: c,
      toHex: toHex,
      amountEther: amountEther,
    );
  }

  @override
  void dispose() {
    EvmRpcPool.disposeAll();
    super.dispose();
  }
}
