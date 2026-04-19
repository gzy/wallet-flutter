import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web3dart/web3dart.dart';

import '../models/app_chain_config.dart';
import '../models/coin_data.dart';
import '../models/evm_network.dart';
import '../models/stored_wallet.dart';
import '../config/evm_environment.dart';
import '../services/evm/evm_client.dart';
import '../services/evm/send_service.dart';
import '../services/evm/transfer_fee_service.dart';
import '../services/evm/token_service.dart';
import '../services/market/app_price_service.dart';
import '../services/wallet/chains_service.dart';
import '../services/wallet/wallet_balance_service.dart';
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
    ChainsService? chainsService,
    WalletBalanceService? walletBalanceService,
  })  : _storage = storage ?? SecureStorageService(),
        _tokenService = tokenService ?? TokenService(),
        _sendService = sendService ?? SendService(),
        _appPriceService = appPriceService ?? AppPriceService(),
        _chainsService = chainsService ?? ChainsService(),
        _walletBalanceService = walletBalanceService ?? WalletBalanceService();

  final SecureStorageService _storage;
  final TokenService _tokenService;
  final SendService _sendService;
  final AppPriceService _appPriceService;
  final ChainsService _chainsService;
  final WalletBalanceService _walletBalanceService;

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

  /// 启动时由 [ChainsService] 拉取，供后续对接 `/api/app/wallet/balance` 等（`chain` 参数与 [AppChainConfig.chainId] 对齐）。
  List<AppChainConfig> _backendChains = [];

  List<AppChainConfig> get backendChains => List.unmodifiable(_backendChains);

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

  /// 与 `GET /api/app/chains` 返回的 `chainId` 对齐，供 `/api/app/wallet/balance` 的 `chain` 查询参数使用。
  String _balanceChainQueryParam(EvmNetworkId networkKey) {
    final want = EvmEnvironment.chainId(networkKey).toString();
    for (final c in _backendChains) {
      if (c.chainType.toUpperCase() != 'EVM') {
        continue;
      }
      if (c.chainId == want) {
        return c.chainId;
      }
    }
    return want;
  }

  /// 与后端钱包接口（余额、交易详情等）的 `chain` 查询参数一致。
  String backendChainParam(EvmNetworkId network) =>
      _balanceChainQueryParam(network);

  /// 当前 [backendChains] 是否包含该 EVM 链（`status == 1` 或未填视为启用）。
  bool backendHasEvmChainId(int chainId) {
    final want = chainId.toString();
    for (final c in _backendChains) {
      if (c.chainType.toUpperCase() != 'EVM') {
        continue;
      }
      if (c.chainId != want) {
        continue;
      }
      if (c.status != null && c.status != 1) {
        continue;
      }
      return true;
    }
    return false;
  }

  Iterable<AppChainConfig> _activeEvmBackendChains() sync* {
    for (final c in _backendChains) {
      if (c.chainType.toUpperCase() != 'EVM') {
        continue;
      }
      if (c.chainId.isEmpty) {
        continue;
      }
      if (c.status != null && c.status != 1) {
        continue;
      }
      yield c;
    }
  }

  String _cryptoListIcon(String symbol) {
    switch (symbol.toUpperCase()) {
      case 'ETH':
        return '⚪';
      case 'USDT':
        return '₮';
      case 'BTC':
        return '₿';
      default:
        final u = symbol.toUpperCase();
        return u.isEmpty ? '◆' : u.substring(0, 1);
    }
  }

  double _nativeBalanceFromRows(List<WalletBalanceEntry> rows, String symbol) {
    final s = symbol.toUpperCase();
    for (final r in rows) {
      if (r.crypto?.toUpperCase() == s) {
        return r.balance;
      }
    }
    return 0;
  }

  Future<void> init() async {
    _initReady = false;
    notifyListeners();
    try {
      _backendChains = await _chainsService.fetchChains();
      if (kDebugMode && _backendChains.isNotEmpty) {
        debugPrint('WalletController: backend chains ${_backendChains.length}');
      }
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
    // 已启用 PIN 且未解锁时不要在后台拉余额：会多次 notifyListeners，主线程在解锁层下仍重建整个 MainTabs。
    if (_credentials != null && (!_pinEnabled || _sessionUnlocked)) {
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
      if (_credentials != null) {
        unawaited(refreshBalances());
      }
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
      final addressHex = addr.hex;
      final quotes = await _appPriceService.fetchAllPrices();
      final backendEvm = _activeEvmBackendChains().toList();
      final coins = <CoinData>[];
      if (backendEvm.isNotEmpty) {
        final seen = <String>{};
        for (final chainCfg in backendEvm) {
          final chainParam = chainCfg.chainId;
          final remote = await _walletBalanceService.fetchBalances(
            address: addressHex,
            chain: chainParam,
          );
          final chainIdInt = int.tryParse(chainCfg.chainId);
          if (remote != null && remote.isNotEmpty) {
            for (final row in remote) {
              final sym = row.crypto?.trim() ?? '';
              if (sym.isEmpty) {
                continue;
              }
              final key = '${chainCfg.chainId}_${sym.toUpperCase()}';
              if (!seen.add(key)) {
                continue;
              }
              AppChainCrypto? meta;
              for (final x in chainCfg.cryptos) {
                if (x.crypto.toUpperCase() == sym.toUpperCase()) {
                  meta = x;
                  break;
                }
              }
              final pair = AppPriceService.usdtPairKeyForSymbol(sym);
              final q = quotes[pair];
              final price = q?.price ?? 0;
              final change = q?.change24h ?? 0;
              final bal = row.balance;
              coins.add(
                CoinData(
                  id: 'evm_${chainCfg.chainId}_${sym.toUpperCase()}',
                  symbol: sym.toUpperCase(),
                  name: meta?.cryptoName ?? sym.toUpperCase(),
                  icon: _cryptoListIcon(sym),
                  network: chainCfg.chainName,
                  chainId: chainIdInt,
                  price: price,
                  priceChange24h: change,
                  balance: bal,
                  balanceUSD: bal * price,
                ),
              );
            }
          } else {
            for (final c in chainCfg.cryptos) {
              if (c.isNative != 1) {
                continue;
              }
              final sym = c.crypto.toUpperCase();
              final key = '${chainCfg.chainId}_$sym';
              if (!seen.add(key)) {
                continue;
              }
              final netId = EvmEnvironment.networkIdForChainId(chainIdInt);
              double bal = 0;
              if (netId != null) {
                bal = await _tokenService.getEthBalanceEther(netId, addr);
              }
              final pair = AppPriceService.usdtPairKeyForSymbol(sym);
              final q = quotes[pair];
              final price = q?.price ?? 0;
              final change = q?.change24h ?? 0;
              coins.add(
                CoinData(
                  id: 'evm_${chainCfg.chainId}_$sym',
                  symbol: sym,
                  name: c.cryptoName ?? sym,
                  icon: _cryptoListIcon(sym),
                  network: chainCfg.chainName,
                  chainId: chainIdInt,
                  price: price,
                  priceChange24h: change,
                  balance: bal,
                  balanceUSD: bal * price,
                ),
              );
            }
          }
        }
      } else {
        for (final cfg in EvmEnvironment.nativeCoins) {
          final chainParam = _balanceChainQueryParam(cfg.networkKey);
          final remote = await _walletBalanceService.fetchBalances(
            address: addressHex,
            chain: chainParam,
            coin: cfg.symbol,
          );
          double bal;
          if (remote == null) {
            bal = await _tokenService.getEthBalanceEther(cfg.networkKey, addr);
          } else {
            bal = _nativeBalanceFromRows(remote, cfg.symbol);
          }
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

  /// 估算当前原生转账矿工费（EIP-1559 优先，失败则 legacy gasPrice）。
  Future<NativeTransferFeeQuote> quoteNativeTransfer({
    required EvmNetworkId network,
    required String toHex,
    required String amountEther,
  }) async {
    final f = address;
    if (f == null) {
      throw StateError('No wallet');
    }
    final cleaned = toHex.trim().replaceAll(RegExp(r'[\s\n\r]+'), '');
    final to = EthereumAddress.fromHex(cleaned);
    return quoteNativeTransferForNetwork(
      network: network,
      from: f,
      to: to,
      amountEther: amountEther,
    );
  }

  Future<String> sendEth({
    required EvmNetworkId network,
    required String toHex,
    required String amountEther,
    int? maxGas,
    EtherAmount? gasPrice,
    EtherAmount? maxFeePerGas,
    EtherAmount? maxPriorityFeePerGas,
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
      maxGas: maxGas,
      gasPrice: gasPrice,
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
    );
  }

  @override
  void dispose() {
    EvmRpcPool.disposeAll();
    super.dispose();
  }
}
