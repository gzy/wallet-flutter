import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web3dart/web3dart.dart';
import 'package:web3dart/crypto.dart'
    show bytesToHex, hexToBytes, hexToInt, sign;
import 'package:crypto/crypto.dart' show sha256;

import '../data/local/app_local_cache.dart';
import '../models/app_chain_config.dart';
import '../models/coin_data.dart';
import '../models/recent_recipient.dart';
import '../models/stored_wallet.dart';
import '../services/market/app_price_service.dart';
import '../services/wallet/chains_service.dart';
import '../services/wallet/wallet_balance_service.dart';
import '../services/wallet/chain_rules.dart';
import '../services/wallet/hd_wallet_service.dart';
import '../services/wallet/mnemonic_service.dart';
import '../services/wallet/secure_storage_service.dart';
import '../services/wallet/solana_backend_transfer.dart';
import '../services/wallet/wallet_transfer_api_service.dart';
import '../services/wallet/tron_utils.dart';

/// 全局钱包状态：多钱包、PIN、助记词派生、EVM 余额、发送交易
class WalletController extends ChangeNotifier {
  WalletController({
    SecureStorageService? storage,
    AppPriceService? appPriceService,
    ChainsService? chainsService,
    WalletBalanceService? walletBalanceService,
    WalletTransferApiService? transferApi,
    AppLocalCache? localCache,
  })  : _storage = storage ?? SecureStorageService(),
        _appPriceService = appPriceService ?? AppPriceService(),
        _chainsService = chainsService ?? ChainsService(),
        _walletBalanceService = walletBalanceService ?? WalletBalanceService(),
        _transferApi = transferApi ?? WalletTransferApiService(),
        _localCache = localCache;

  final SecureStorageService _storage;
  final AppPriceService _appPriceService;
  final ChainsService _chainsService;
  final WalletBalanceService _walletBalanceService;
  final WalletTransferApiService _transferApi;
  final AppLocalCache? _localCache;

  /// 非敏感只读缓存（Drift），供地址簿/币种详情等使用。
  AppLocalCache? get localCache => _localCache;

  static const _uuid = Uuid();

  List<StoredWallet> _wallets = [];
  String? _activeWalletId;
  EthPrivateKey? _credentials;
  String? _addressHex;
  Uint8List? _tronPrivateKey;
  String? _tronAddress;
  String? _solanaAddress;
  String? _xrpAddress;
  bool _backedUp = false;
  bool _loading = false;

  /// 首页网络筛选：后端钱包接口使用的 `chain` 查询参数（优先 chainCode，缺失则 chainId 字符串）。
  /// `null` 表示“全部网络”。
  String? _sendChain;
  bool _pinEnabled = false;
  bool _sessionUnlocked = true;
  bool _initReady = false;
  bool _appInBackground = false;
  static const Duration _pinGraceDuration = Duration(minutes: 30);
  int? _lastSessionUnlockAtMs;

  List<CoinData> _evmCoins = [];
  Set<String> _hiddenCoinIds = <String>{};

  /// 启动时由 [ChainsService] 拉取，供后续对接 `/api/app/wallet/balance` 等（`chain` 参数与 [AppChainConfig.walletApiChainQuery] 对齐）。
  List<AppChainConfig> _backendChains = [];

  List<AppChainConfig> get backendChains => List.unmodifiable(_backendChains);

  bool get hasWallet => _credentials != null;
  String? get addressHex => _addressHex;
  String? get tronAddress => _tronAddress;
  String? get solanaAddress => _solanaAddress;
  String? get xrpAddress => _xrpAddress;
  EthereumAddress? get address =>
      _addressHex == null ? null : EthereumAddress.fromHex(_addressHex!);
  bool get backedUp => _backedUp;
  bool get loading => _loading;
  String? get sendChain => _sendChain;
  List<CoinData> get evmCoins => List.unmodifiable(_evmCoins);
  bool isCoinVisible(String coinId) => !_hiddenCoinIds.contains(coinId);
  Set<String> get hiddenCoinIds => Set.unmodifiable(_hiddenCoinIds);

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
  bool get appInBackground => _appInBackground;

  bool _isWithinPinGrace(int nowMs) {
    final at = _lastSessionUnlockAtMs;
    if (at == null || at <= 0) return false;
    return nowMs - at <= _pinGraceDuration.inMilliseconds;
  }

  Future<void> _loadPinGraceForActiveWallet() async {
    final wid = _activeWalletId;
    if (wid == null) {
      _lastSessionUnlockAtMs = null;
      return;
    }
    _lastSessionUnlockAtMs = await _storage.readPinSessionUnlockAtMs(wid);
  }

  /// 生命周期：进入后台/不可见时调用。
  ///
  /// 需求：切后台时不要显示 PIN，也不要黑屏（App 切换器里保持正常页面快照）。
  /// 因此只标记后台态，用于在 UI 层抑制 UnlockScreen；
  /// 同时**不**在这里把 [_sessionUnlocked] 置为 false，否则 `_HomeShell` 会渲染纯色底导致切换器快照变黑。
  /// “上锁”的动作延迟到回前台时判断（若已超 30 分钟才真正进入锁屏态）。
  void onAppBackgrounded() {
    _appInBackground = true;
    notifyListeners();
  }

  /// 生命周期：回到前台时调用。
  ///
  /// 规则：
  /// - 切后台时不展示 PIN、不黑屏（保持切换器快照）
  /// - 回前台时再判断：30 分钟内免 PIN，否则进入锁屏态要求输入 PIN
  /// - 一直前台不自动上锁（无定时器）
  void onAppResumed() {
    if (!_pinEnabled || _credentials == null) {
      if (_appInBackground) {
        _appInBackground = false;
        notifyListeners();
      }
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    // 回前台再决定是否需要锁屏（避免切换器黑屏/闪 PIN）
    _sessionUnlocked = _isWithinPinGrace(now);
    _appInBackground = false;
    notifyListeners();
    if (_sessionUnlocked) {
      unawaited(refreshBalances());
    }
  }

  void setSendChain(String? chainQuery) {
    final q = chainQuery?.trim();
    if (q == null || q.isEmpty) {
      _sendChain = null;
      notifyListeners();
      return;
    }
    for (final c in _activeBackendChains()) {
      if (c.walletApiChainQuery == q) {
        _sendChain = q;
        notifyListeners();
        return;
      }
    }
  }

  void _ensureSendChainDefault() {
    final chains = _activeBackendChains().toList();
    if (chains.isEmpty) {
      _sendChain = null;
      return;
    }
    // 默认显示「全部网络」：仅在用户已手动选择过某条链时才保持该选择。
    // 若当前选择已不再可用（链下架/禁用），则回退到「全部」而不是强行选第一条链。
    if (_sendChain == null) {
      return;
    }
    if (chains.any((c) => c.walletApiChainQuery == _sendChain)) {
      return;
    }
    _sendChain = null;
  }

  /// 与 `GET /api/app/chains` 中 EVM 项匹配（按 [AppChainConfig.chainId] 字符串比较）。
  AppChainConfig? _appChainConfigForChainId(int? chainId) {
    if (chainId == null) {
      return null;
    }
    final want = chainId.toString();
    for (final c in _backendChains) {
      if (c.chainType.toUpperCase() != 'EVM') {
        continue;
      }
      if (c.chainId == want) {
        return c;
      }
    }
    return null;
  }

  /// 与后端钱包接口（余额、交易历史/详情等）的 `chain` 查询参数一致（优先 `chainCode`）。
  String backendChainParamForChainId(int? chainId) {
    final hit = _appChainConfigForChainId(chainId);
    if (hit != null) {
      return hit.walletApiChainQuery;
    }
    return chainId?.toString() ?? '';
  }

  /// [CoinData] 上若已写入 [CoinData.walletApiChainQuery] 则优先；否则再按链 ID 查表。
  String chainParamForCoin(CoinData coin) {
    final q = coin.walletApiChainQuery?.trim();
    if (q != null && q.isNotEmpty) {
      return q;
    }
    return backendChainParamForChainId(coin.chainId);
  }

  /// 地址簿「最近」：与当前链 `chain` 查询参数一致时展示（见 [chainParamForCoin]）。
  Future<List<RecentRecipient>> recentRecipientsForChain(
      String chainQuery) async {
    final id = _activeWalletId;
    if (id == null) {
      return const [];
    }
    return _storage.readRecentRecipientsForChain(id, chainQuery);
  }

  /// 成功广播后写入，供 [recentRecipientsForChain] 使用。
  Future<void> recordRecentTransferRecipient({
    required String chain,
    required String address,
  }) async {
    final id = _activeWalletId;
    if (id == null) {
      return;
    }
    await _storage.recordRecentRecipient(
      walletId: id,
      chain: chain,
      address: address,
    );
  }

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

  Iterable<AppChainConfig> _activeBackendChains() sync* {
    for (final c in _backendChains) {
      if (c.walletApiChainQuery.trim().isEmpty) {
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

  /// 拉取单条链的余额并组装 [CoinData]；`null` 表示无主地址或接口失败（全量刷新时跳过该链；单链刷新时保留旧数据）。
  Future<List<CoinData>?> _loadCoinsForChainConfig(
    AppChainConfig chainCfg,
    Map<String, AppSymbolQuote> quotes,
  ) async {
    final creds = _credentials;
    if (creds == null) {
      return null;
    }
    final chainParam = chainCfg.walletApiChainQuery;
    final kind = ChainRules.kindForAppChain(chainCfg);
    final addressHex = creds.address.hex;
    final tronAddr = _tronAddress;
    final ownerAddress = switch (kind) {
      ChainKind.tron => tronAddr ?? '',
      ChainKind.solana => _solanaAddress ?? '',
      ChainKind.xrp => _xrpAddress ?? '',
      ChainKind.evm || ChainKind.unknown => addressHex,
    };
    if (ownerAddress.isEmpty) {
      return null;
    }
    if (kDebugMode) {
      debugPrint(
        'refreshBalances: chain=$chainParam kind=$kind address=$ownerAddress',
      );
    }
    final List<WalletBalanceEntry>? remote;
    if (kind == ChainKind.solana || kind == ChainKind.xrp) {
      final symbols = <String>[];
      for (final e in chainCfg.cryptos) {
        final s = e.crypto.trim();
        if (s.isNotEmpty && !symbols.contains(s)) {
          symbols.add(s);
        }
      }
      if (symbols.isEmpty) {
        final fb = chainCfg.symbol.trim();
        if (fb.isNotEmpty) {
          symbols.add(fb);
        }
      }
      if (symbols.isEmpty) {
        return null;
      }
      final parts = await Future.wait(
        symbols.map(
          (crypto) => _walletBalanceService.fetchBalances(
            address: ownerAddress,
            chain: chainParam,
            chainType: chainCfg.chainType,
            crypto: crypto,
          ),
        ),
      );
      if (parts.any((p) => p == null)) {
        return null;
      }
      final byCrypto = <String, WalletBalanceEntry>{};
      for (final p in parts) {
        for (final row in p!) {
          final k = (row.crypto ?? '').trim().toUpperCase();
          if (k.isNotEmpty) {
            byCrypto[k] = row;
          }
        }
      }
      remote = byCrypto.values.toList();
    } else {
      remote = await _walletBalanceService.fetchBalances(
        address: ownerAddress,
        chain: chainParam,
        chainType: chainCfg.chainType,
      );
    }
    if (remote == null) {
      return null;
    }
    final chainIdInt =
        kind == ChainKind.evm ? int.tryParse(chainCfg.chainId) : null;
    final coins = <CoinData>[];
    final seen = <String>{};
    if (remote.isNotEmpty) {
      for (final row in remote) {
        final sym = row.crypto?.trim() ?? '';
        if (sym.isEmpty) {
          continue;
        }
        final key = '${chainCfg.backendStableSegment}_${sym.toUpperCase()}';
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
        final q = AppPriceService.resolveQuote(sym, quotes[pair]);
        final price = q.price;
        final change = q.change24h;
        final bal = row.balance;
        coins.add(
          CoinData(
            id: chainCfg.coinPrimaryId(sym),
            symbol: sym.toUpperCase(),
            name: meta?.cryptoName ?? sym.toUpperCase(),
            icon: _cryptoListIcon(sym),
            network: chainCfg.chainName,
            chainId: chainIdInt,
            walletApiChainQuery: chainParam,
            txUrlPrefix: chainCfg.txUrlPrefix,
            addressUrlPrefix: chainCfg.addressUrlPrefix,
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
        final key = '${chainCfg.backendStableSegment}_$sym';
        if (!seen.add(key)) {
          continue;
        }
        final pair = AppPriceService.usdtPairKeyForSymbol(sym);
        final q = AppPriceService.resolveQuote(sym, quotes[pair]);
        final price = q.price;
        final change = q.change24h;
        const bal = 0.0;
        coins.add(
          CoinData(
            id: chainCfg.coinPrimaryId(sym),
            symbol: sym,
            name: c.cryptoName ?? sym,
            icon: _cryptoListIcon(sym),
            network: chainCfg.chainName,
            chainId: chainIdInt,
            walletApiChainQuery: chainParam,
            txUrlPrefix: chainCfg.txUrlPrefix,
            addressUrlPrefix: chainCfg.addressUrlPrefix,
            price: price,
            priceChange24h: change,
            balance: bal,
            balanceUSD: bal * price,
          ),
        );
      }
    }
    return coins;
  }

  /// 币种详情等处：只刷新 `_backendChains` 中某条 `walletApiChainQuery`，减少无关链请求。
  Future<void> refreshBalancesForWalletApiChain(
      String walletApiChainQuery) async {
    if (_credentials == null) {
      return;
    }
    final want = walletApiChainQuery.trim();
    if (want.isEmpty) {
      return;
    }
    AppChainConfig? cfg;
    for (final c in _activeBackendChains()) {
      if (c.walletApiChainQuery.trim().toUpperCase() == want.toUpperCase()) {
        cfg = c;
        break;
      }
    }
    if (cfg == null) {
      return;
    }
    _loading = true;
    notifyListeners();
    try {
      var quotes = await _appPriceService.fetchAllPrices();
      if (quotes.isEmpty) {
        final cachedQ = await _localCache?.getPriceQuotes();
        if (cachedQ != null && cachedQ.isNotEmpty) {
          quotes = cachedQ;
        }
      }
      final replacement = await _loadCoinsForChainConfig(cfg, quotes);
      if (replacement == null) {
        return;
      }
      final qUpper = cfg.walletApiChainQuery.trim().toUpperCase();
      final others = _evmCoins
          .where(
            (c) => (c.walletApiChainQuery ?? '').trim().toUpperCase() != qUpper,
          )
          .toList();
      _evmCoins = [...others, ...replacement];
      _ensureSendChainDefault();

      final wid = _activeWalletId;
      if (wid != null) {
        unawaited(_localCache?.putEvmCoinsForWallet(wid, _evmCoins));
        if (quotes.isNotEmpty) {
          unawaited(_localCache?.putPriceQuotes(quotes));
        }
      }
    } catch (e, st) {
      debugPrint('refreshBalancesForWalletApiChain: $e\n$st');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> init() async {
    _initReady = false;
    notifyListeners();
    try {
      if (kDebugMode) {
        debugPrint('WalletController.init: start');
      }
      _backendChains = await _chainsService.fetchChains();
      if (_backendChains.isNotEmpty) {
        unawaited(_localCache?.putChains(_backendChains));
      } else {
        final cached = await _localCache?.getChains();
        if (cached != null && cached.isNotEmpty) {
          _backendChains = cached;
        }
      }
      _ensureSendChainDefault();
      if (kDebugMode && _backendChains.isNotEmpty) {
        debugPrint('WalletController: backend chains ${_backendChains.length}');
      }
      if (kDebugMode) {
        debugPrint('WalletController.init: read pin');
      }
      _pinEnabled = await _storage.hasPin();
      if (kDebugMode) {
        debugPrint('WalletController.init: read wallet list');
      }
      _wallets = await _storage.readWalletList();
      if (kDebugMode) {
        debugPrint('WalletController.init: reconcile legacy keys');
      }
      await _reconcileBackedUpFromLegacyKeys();
      if (kDebugMode) {
        debugPrint('WalletController.init: read active wallet id');
      }
      _activeWalletId = await _storage.getActiveWalletId();
      if (_activeWalletId == null && _wallets.isNotEmpty) {
        _activeWalletId = _wallets.first.id;
        await _storage.setActiveWalletId(_activeWalletId!);
      }
      if (_activeWalletId != null) {
        _hiddenCoinIds =
            await _storage.readHiddenCoinIdsForWallet(_activeWalletId!);
      } else {
        _hiddenCoinIds = <String>{};
      }
      if (_pinEnabled) {
        _sessionUnlocked = false;
      } else {
        _sessionUnlocked = true;
      }
      if (kDebugMode) {
        debugPrint('WalletController.init: load credentials');
      }
      await _loadCredentialsFromActiveMnemonic();
      if (_pinEnabled && _credentials != null) {
        await _loadPinGraceForActiveWallet();
        final now = DateTime.now().millisecondsSinceEpoch;
        if (_isWithinPinGrace(now)) {
          _sessionUnlocked = true;
        }
      }
    } catch (e, st) {
      debugPrint('WalletController.init failed: $e\n$st');
    } finally {
      _initReady = true;
      notifyListeners();
      if (kDebugMode) {
        debugPrint('WalletController.init: done');
      }
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

  Future<void> _applyDerivedKeysFromMnemonic(String m) async {
    _credentials = HdWalletService.privateKeyFromMnemonic(m);
    _addressHex = _credentials!.address.hex;
    final tronPk = Uint8List.fromList(
      HdWalletService.tronPrivateKeyBytesFromMnemonic(m),
    );
    _tronPrivateKey = tronPk;
    _tronAddress = tronAddressFromPrivateKeyBytes(tronPk);
    try {
      _solanaAddress = await HdWalletService.solanaAddressFromMnemonic(m);
    } catch (e, st) {
      debugPrint('Solana derive failed: $e\n$st');
      _solanaAddress = null;
    }
    try {
      _xrpAddress = HdWalletService.xrpAddressFromMnemonic(m);
    } catch (e, st) {
      debugPrint('XRP derive failed: $e\n$st');
      _xrpAddress = null;
    }
  }

  Future<void> _loadCredentialsFromActiveMnemonic() async {
    _credentials = null;
    _addressHex = null;
    _tronPrivateKey = null;
    _tronAddress = null;
    _solanaAddress = null;
    _xrpAddress = null;
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
      await _applyDerivedKeysFromMnemonic(m);
      final idx = _wallets.indexWhere((w) => w.id == id);
      _backedUp = idx >= 0
          ? _wallets[idx].backedUp
          : await _storage.readBackedUpForWallet(id);
    } catch (e, st) {
      debugPrint('Wallet init failed: $e\n$st');
      _credentials = null;
      _addressHex = null;
      _tronPrivateKey = null;
      _tronAddress = null;
      _solanaAddress = null;
      _xrpAddress = null;
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
    try {
      await _applyDerivedKeysFromMnemonic(m);
    } catch (e, st) {
      debugPrint('createWallet derive failed: $e\n$st');
      _credentials = null;
      _addressHex = null;
      _tronPrivateKey = null;
      _tronAddress = null;
      _solanaAddress = null;
      _xrpAddress = null;
    }
    _backedUp = false;
    _sessionUnlocked = true;
    if (_pinEnabled) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _lastSessionUnlockAtMs = now;
      unawaited(_storage.writePinSessionUnlockAtMs(id, now));
    }
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
    try {
      await _applyDerivedKeysFromMnemonic(phrase);
    } catch (e, st) {
      debugPrint('importWallet derive failed: $e\n$st');
      _credentials = null;
      _addressHex = null;
      _tronPrivateKey = null;
      _tronAddress = null;
      _solanaAddress = null;
      _xrpAddress = null;
    }
    _backedUp = false;
    _sessionUnlocked = true;
    if (_pinEnabled) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _lastSessionUnlockAtMs = now;
      unawaited(_storage.writePinSessionUnlockAtMs(id, now));
    }
    await refreshBalances();
    notifyListeners();
  }

  Future<void> switchWallet(String id) async {
    if (!_wallets.any((w) => w.id == id)) {
      return;
    }
    await _storage.setActiveWalletId(id);
    _activeWalletId = id;
    _hiddenCoinIds = await _storage.readHiddenCoinIdsForWallet(id);
    if (_pinEnabled) {
      _sessionUnlocked = false;
    }
    await _loadCredentialsFromActiveMnemonic();
    await _loadPinGraceForActiveWallet();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_pinEnabled && _credentials != null && _isWithinPinGrace(now)) {
      _sessionUnlocked = true;
    }
    notifyListeners();
    if (_credentials != null && (!_pinEnabled || _sessionUnlocked)) {
      unawaited(refreshBalances());
    }
  }

  Future<void> setCoinVisible(String coinId, bool visible) async {
    final id = _activeWalletId;
    if (id == null) return;
    final next = Set<String>.from(_hiddenCoinIds);
    if (visible) {
      next.remove(coinId);
    } else {
      next.add(coinId);
    }
    _hiddenCoinIds = next;
    notifyListeners();
    await _storage.writeHiddenCoinIdsForWallet(id, _hiddenCoinIds);
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
    unawaited(_localCache?.clearEvmCoinsForWallet(id));
    final next = _wallets.where((w) => w.id != id).toList();
    await _storage.writeWalletList(next);
    _wallets = next;

    if (_activeWalletId == id) {
      if (next.isEmpty) {
        _activeWalletId = null;
        await _storage.clearActiveWalletId();
        _credentials = null;
        _addressHex = null;
        _tronPrivateKey = null;
        _tronAddress = null;
        _solanaAddress = null;
        _xrpAddress = null;
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

  /// 根据助记词推导该钱包的 Tron 地址（Base58Check，T...），不切换当前钱包。
  Future<String?> readTronAddressForWallet(String walletId) async {
    final m = await _storage.readMnemonicForWallet(walletId);
    if (m == null || m.isEmpty) {
      return null;
    }
    try {
      final pk = Uint8List.fromList(
        HdWalletService.tronPrivateKeyBytesFromMnemonic(m),
      );
      return tronAddressFromPrivateKeyBytes(pk);
    } catch (e, st) {
      debugPrint('readTronAddressForWallet: $e\n$st');
      return null;
    }
  }

  /// 根据助记词推导该钱包的 Solana 地址（Base58），不切换当前钱包。
  Future<String?> readSolanaAddressForWallet(String walletId) async {
    final m = await _storage.readMnemonicForWallet(walletId);
    if (m == null || m.isEmpty) {
      return null;
    }
    try {
      return await HdWalletService.solanaAddressFromMnemonic(m);
    } catch (e, st) {
      debugPrint('readSolanaAddressForWallet: $e\n$st');
      return null;
    }
  }

  /// 根据助记词推导该钱包的 XRP Classic 地址（`r...`），不切换当前钱包。
  Future<String?> readXrpAddressForWallet(String walletId) async {
    final m = await _storage.readMnemonicForWallet(walletId);
    if (m == null || m.isEmpty) {
      return null;
    }
    try {
      return HdWalletService.xrpAddressFromMnemonic(m);
    } catch (e, st) {
      debugPrint('readXrpAddressForWallet: $e\n$st');
      return null;
    }
  }

  Future<PinVerifyResult> verifyTransactionPin(String pin) =>
      _storage.verifyPin(pin);

  Future<PinVerifyResult> unlockSession(String pin) async {
    final r = await _storage.verifyPin(pin);
    if (r.ok) {
      _sessionUnlocked = true;
      final wid = _activeWalletId;
      if (wid != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        _lastSessionUnlockAtMs = now;
        unawaited(_storage.writePinSessionUnlockAtMs(wid, now));
      }
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
      var quotes = await _appPriceService.fetchAllPrices();
      if (quotes.isEmpty) {
        final cachedQ = await _localCache?.getPriceQuotes();
        if (cachedQ != null && cachedQ.isNotEmpty) {
          quotes = cachedQ;
        }
      }
      final backendChains = _activeBackendChains().toList();
      var anyBalanceRequestOk = backendChains.isEmpty;
      final coins = <CoinData>[];
      if (backendChains.isNotEmpty) {
        final seen = <String>{};
        for (final chainCfg in backendChains) {
          final partial = await _loadCoinsForChainConfig(chainCfg, quotes);
          if (partial == null) {
            continue;
          }
          anyBalanceRequestOk = true;
          for (final cd in partial) {
            final key =
                '${chainCfg.backendStableSegment}_${cd.symbol.toUpperCase()}';
            if (!seen.add(key)) {
              continue;
            }
            coins.add(cd);
          }
        }
      }
      // 无网时各链常返回 null（非抛错），下面会造出全 0 列表；用 Drift 上次快照，避免全 0 占屏、勿把好缓存写坏
      if (backendChains.isNotEmpty && !anyBalanceRequestOk) {
        final wid = _activeWalletId;
        if (wid != null) {
          final snap = await _localCache?.getEvmCoinsForWallet(wid);
          if (snap != null && snap.isNotEmpty) {
            _evmCoins = snap;
            _ensureSendChainDefault();
            if (quotes.isNotEmpty) {
              unawaited(_localCache?.putPriceQuotes(quotes));
            }
            return;
          }
        }
      }
      _evmCoins = coins;
      _ensureSendChainDefault();
      final wid = _activeWalletId;
      if (wid != null) {
        if (anyBalanceRequestOk) {
          unawaited(_localCache?.putEvmCoinsForWallet(wid, coins));
        }
        if (quotes.isNotEmpty) {
          unawaited(_localCache?.putPriceQuotes(quotes));
        }
      }
    } catch (e, st) {
      debugPrint('refreshBalances: $e\n$st');
      final wid = _activeWalletId;
      if (wid != null) {
        final snap = await _localCache?.getEvmCoinsForWallet(wid);
        if (snap != null && snap.isNotEmpty) {
          _evmCoins = snap;
        }
      }
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

  static Map<String, dynamic> _asMap(Object? v) {
    if (v is Map) {
      return Map<String, dynamic>.from(v);
    }
    throw const FormatException('expected map');
  }

  static int _readIntFromMaybeHex(Object? v) {
    if (v is int) {
      return v;
    }
    if (v is String) {
      if (v.startsWith('0x') || v.startsWith('0X')) {
        return int.parse(v.substring(2), radix: 16);
      }
      return int.parse(v);
    }
    if (v is num) {
      return v.toInt();
    }
    throw FormatException('expected int, got $v');
  }

  static BigInt _readWeiFromMaybeHex(Object? v) {
    if (v is int) {
      return BigInt.from(v);
    }
    if (v is String) {
      return hexToInt(v);
    }
    if (v is num) {
      return BigInt.from(v.toInt());
    }
    throw FormatException('expected hex wei, got $v');
  }

  static Uint8List _readTxData(Object? v) {
    if (v == null) {
      return Uint8List(0);
    }
    if (v is! String) {
      throw const FormatException('data must be hex string');
    }
    final s = v.trim();
    if (s.isEmpty || s == '0x' || s == '0X') {
      return Uint8List(0);
    }
    return hexToBytes(s);
  }

  static String? _readTxHashFromBroadcast(data) {
    if (data == null) {
      return null;
    }
    if (data is String) {
      return data;
    }
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      final keys = <String>['txHash', 'hash', 'transactionHash', 'txid'];
      for (final k in keys) {
        final v = m[k];
        if (v is String && v.isNotEmpty) {
          return v;
        }
      }
    }
    return null;
  }

  /// 走后端 `createTransaction` + 本地 legacy 签名 + `broadcastTransaction` 广播；返回 `txHash`（若响应未提供则回退 raw）。
  Future<String> createSignBroadcastBackendTransfer({
    required String chain,
    required String coin,
    required String toAddress,
    required num amount,
    String? gasPriceType,
  }) async {
    final key = _credentials;
    if (key == null) {
      throw StateError('No wallet');
    }
    final cfg = backendChains.firstWhere(
      (c) => c.walletApiChainQuery == chain,
      orElse: () => const AppChainConfig(
        chainId: '',
        chainType: 'EVM',
        chainName: '',
        symbol: '',
      ),
    );
    final kind = ChainRules.kindForAppChain(cfg);

    if (kind == ChainKind.solana) {
      final wid = _activeWalletId;
      if (wid == null) {
        throw StateError('未选择钱包');
      }
      final phrase = await _storage.readMnemonicForWallet(wid);
      if (phrase == null || phrase.trim().isEmpty) {
        throw StateError('无法读取助记词');
      }
      final owner = _solanaAddress;
      if (owner == null || owner.isEmpty) {
        throw StateError('Solana 地址未就绪');
      }
      final create = await _transferApi.createTransaction(
        chain: chain,
        coin: coin,
        ownerAddress: owner,
        toAddress: toAddress,
        amount: amount,
        chainType: cfg.chainType,
      );
      if (create == null) {
        throw StateError('createTransaction 无响应');
      }
      if (create['code'] != 0) {
        final msg = create['message']?.toString() ?? 'createTransaction 失败';
        throw StateError(msg);
      }
      final data = _asMap(create['data']);
      final signer = await SolanaBackendTransfer.keyPairFromMnemonic(phrase);
      if (signer.address != owner) {
        throw StateError('Solana 派生地址与当前展示地址不一致');
      }
      final signedB64 = await SolanaBackendTransfer.signCreateTransactionData(
        data: data,
        signer: signer,
        expectedOwnerBase58: owner,
        amountSol: amount,
      );
      final broad = await _transferApi.broadcastTransaction(
        chain: chain,
        coin: coin,
        data: signedB64,
        chainType: cfg.chainType,
      );
      if (broad == null) {
        throw StateError('broadcastTransaction 无响应');
      }
      if (broad['code'] != 0) {
        final msg = broad['message']?.toString() ?? 'broadcastTransaction 失败';
        throw StateError(msg);
      }
      final h = _readTxHashFromBroadcast(broad['data']);
      return h ?? signedB64;
    }

    if (kind == ChainKind.xrp) {
      throw StateError('XRP 链转账签名尚未接入，请等待后续版本');
    }

    if (kind == ChainKind.tron) {
      final pk = _tronPrivateKey;
      final owner = _tronAddress;
      if (pk == null || owner == null || owner.isEmpty) {
        throw StateError('Tron 钱包未初始化');
      }
      final create = await _transferApi.createTransaction(
        chain: chain,
        coin: coin,
        ownerAddress: owner,
        toAddress: toAddress,
        amount: amount,
        chainType: cfg.chainType,
      );
      if (create == null) {
        throw StateError('createTransaction 无响应');
      }
      if (create['code'] != 0) {
        final msg = create['message']?.toString() ?? 'createTransaction 失败';
        throw StateError(msg);
      }
      // 先尽可能兼容不同字段命名；并打印样例便于与你后端对齐
      if (kDebugMode) {
        debugPrint('TRON createTransaction resp: $create');
      }
      final data = _asMap(create['data']);
      final rawHex = (data['rawDataHex'] ??
              data['raw_data_hex'] ??
              (data['transaction'] is Map
                  ? (data['transaction'] as Map)['raw_data_hex']
                  : null))
          ?.toString();
      if (rawHex == null || rawHex.trim().isEmpty) {
        throw StateError('TRON createTransaction 缺少 rawDataHex/raw_data_hex');
      }
      final rawBytes = tronHexToBytes(rawHex);
      final digest = sha256.convert(rawBytes).bytes;
      final sig = sign(Uint8List.fromList(digest), pk);
      final sigBytes = Uint8List(65);
      final rBytes = _uint256To32(sig.r);
      final sBytes = _uint256To32(sig.s);
      sigBytes.setRange(0, 32, rBytes);
      sigBytes.setRange(32, 64, sBytes);
      // web3dart 的 v 为 27/28（以太坊传统），Tron 期望 recoveryId 为 0/1。
      final recId = sig.v >= 27 ? (sig.v - 27) : sig.v;
      sigBytes[64] = recId;
      final sigHex = bytesToHex(sigBytes, include0x: false);

      Map<String, dynamic> txMap;
      final tx = data['transaction'];
      if (tx is Map) {
        txMap = Map<String, dynamic>.from(tx);
      } else {
        txMap = Map<String, dynamic>.from(data);
      }
      txMap['signature'] = [sigHex];
      final broad = await _transferApi.broadcastTransaction(
        chain: chain,
        coin: coin,
        data: jsonEncode(txMap),
        chainType: cfg.chainType,
      );
      if (kDebugMode) {
        debugPrint('TRON broadcastTransaction resp: $broad');
      }
      if (broad == null) {
        throw StateError('broadcastTransaction 无响应');
      }
      if (broad['code'] != 0) {
        final msg = broad['message']?.toString() ?? 'broadcastTransaction 失败';
        throw StateError(msg);
      }
      final h = _readTxHashFromBroadcast(broad['data']);
      return h ?? (data['txId']?.toString() ?? sigHex);
    }

    final create = await _transferApi.createTransaction(
      chain: chain,
      coin: coin,
      ownerAddress: _addressHex ?? '',
      toAddress: toAddress,
      amount: amount,
      gasPriceType: gasPriceType,
      chainType: cfg.chainType,
    );
    if (create == null) {
      throw StateError('createTransaction 无响应');
    }
    if (create['code'] != 0) {
      final msg = create['message']?.toString() ?? 'createTransaction 失败';
      throw StateError(msg);
    }
    final d = _asMap(create['data']);
    final to = EthereumAddress.fromHex(d['to'].toString());
    final valueWei = _readWeiFromMaybeHex(d['value']);
    final gasPrice = EtherAmount.inWei(_readWeiFromMaybeHex(d['gasPrice']));
    final maxGas = _readIntFromMaybeHex(d['gasLimit']);
    final nonce = _readIntFromMaybeHex(d['nonce']);
    final chainId = _readIntFromMaybeHex(d['chainId']);
    final dataBytes = _readTxData(d['data']);

    final tx = Transaction(
      to: to,
      maxGas: maxGas,
      gasPrice: gasPrice,
      value: EtherAmount.inWei(valueWei),
      data: dataBytes,
      nonce: nonce,
    );

    final raw = signTransactionRaw(tx, key, chainId: chainId);
    final signed = bytesToHex(raw, include0x: true);

    final broad = await _transferApi.broadcastTransaction(
      chain: chain,
      coin: coin,
      data: signed,
      chainType: cfg.chainType,
    );
    if (broad == null) {
      throw StateError('broadcastTransaction 无响应');
    }
    if (broad['code'] != 0) {
      final msg = broad['message']?.toString() ?? 'broadcastTransaction 失败';
      throw StateError(msg);
    }
    final h = _readTxHashFromBroadcast(broad['data']);
    return h ?? signed;
  }

  static Uint8List _uint256To32(BigInt v) {
    final out = Uint8List(32);
    var x = v;
    for (var i = 31; i >= 0; i--) {
      out[i] = (x & BigInt.from(0xff)).toInt();
      x = x >> 8;
    }
    return out;
  }
}
