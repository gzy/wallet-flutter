import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web3dart/web3dart.dart';
import 'package:web3dart/crypto.dart'
    show bytesToHex, hexToBytes, hexToInt;
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
import '../services/debug/home_refresh_profiler.dart';
import '../services/wallet/btc_backend_transfer.dart';
import '../services/wallet/solana_backend_transfer.dart';
import '../services/wallet/ton_backend_transfer.dart';
import '../services/wallet/xrp_backend_transfer.dart';
import '../services/wallet/wallet_transfer_api_service.dart';
import '../services/wallet/wallet_transaction_service.dart';
import '../services/wallet/wallet_estimate_gas_service.dart';
import '../services/wallet/wallet_gas_price_service.dart';
import '../services/wallet/tron_utils.dart';
import '../services/wallet/tron_transaction_signer.dart';
import '../services/wallet/tron_resource_service.dart';
import '../models/tron_resource_preorder_dto.dart';
import '../models/tron_resource_confirm_vo.dart';
import '../services/wallet/wallet_key_derivation.dart';

/// 为 `true` 时 DOGE 签名后不调用 `broadcastTransaction`，仅打印请求体供后端验签。
/// 联调完成后改回 `false`。
const bool kDogeSkipBroadcastForBackendTest = false;

/// 全局钱包状态：多钱包、PIN、助记词派生、EVM 余额、发送交易
class WalletController extends ChangeNotifier {
  WalletController({
    SecureStorageService? storage,
    AppPriceService? appPriceService,
    ChainsService? chainsService,
    WalletBalanceService? walletBalanceService,
    WalletTransferApiService? transferApi,
    TronResourceService? tronResourceService,
    AppLocalCache? localCache,
  })  : _storage = storage ?? SecureStorageService(),
        _appPriceService = appPriceService ?? AppPriceService(),
        _chainsService = chainsService ?? ChainsService(),
        _walletBalanceService = walletBalanceService ?? WalletBalanceService(),
        _transferApi = transferApi ?? WalletTransferApiService(),
        _tronResourceService = tronResourceService ?? TronResourceService(),
        _localCache = localCache;

  final SecureStorageService _storage;
  final AppPriceService _appPriceService;
  final ChainsService _chainsService;
  final WalletBalanceService _walletBalanceService;
  final WalletTransferApiService _transferApi;
  final TronResourceService _tronResourceService;
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
  String? _tonAddressMain;
  String? _tonAddressTest;
  String? _btcMainnetAddress;
  String? _btcTestnetAddress;
  String? _dogeMainnetAddress;
  String? _dogeTestnetAddress;
  bool _backedUp = false;
  bool _loading = false;

  /// 首页网络筛选：后端钱包接口使用的 `chain` 查询参数（优先 chainCode，缺失则 chainId 字符串）。
  /// `null` 表示“全部网络”。
  String? _sendChain;
  bool _pinEnabled = false;
  bool _sessionUnlocked = true;
  bool _initReady = false;
  bool _appInBackground = false;
  /// 离开 App 进入后台后，超过该时长再回前台需重新输入 PIN。
  static const Duration _pinBackgroundGraceDuration = Duration(minutes: 30);
  int? _lastBackgroundedAtMs;

  List<CoinData> _evmCoins = [];
  Set<String> _hiddenCoinIds = <String>{};
  List<String> _coinOrderIds = [];

  /// 转账成功后递增；币种详情等监听此值以刷新交易列表。
  int _txHistoryRefreshTick = 0;
  int get txHistoryRefreshTick => _txHistoryRefreshTick;

  /// 启动时由 [ChainsService] 拉取，供后续对接 `/api/app/wallet/balance` 等（`chain` 参数与 [AppChainConfig.walletApiChainQuery] 对齐）。
  List<AppChainConfig> _backendChains = [];

  List<AppChainConfig> get backendChains => List.unmodifiable(_backendChains);

  bool get hasWallet => _credentials != null;

  /// 本地是否已有钱包记录（用于启动路由；派生完成前 [hasWallet] 可能仍为 false）。
  bool get hasStoredWallet => _wallets.isNotEmpty;
  String? get addressHex => _addressHex;
  String? get tronAddress => _tronAddress;
  String? get solanaAddress => _solanaAddress;
  String? get xrpAddress => _xrpAddress;
  String? get tonAddressMain => _tonAddressMain;
  String? get tonAddressTest => _tonAddressTest;
  String? get btcMainnetAddress => _btcMainnetAddress;
  String? get btcTestnetAddress => _btcTestnetAddress;
  String? get dogeMainnetAddress => _dogeMainnetAddress;
  String? get dogeTestnetAddress => _dogeTestnetAddress;

  /// 按链配置（浏览器 / chainCode）选择主网或测试网 BIP84 地址。
  String? btcAddressForChainConfig(AppChainConfig cfg) =>
      _btcOwnerAddressFor(cfg);

  /// 转账/校验「付款地址」：与 [_loadCoinsForChainConfig] 的 owner 规则一致。
  String? ownerAddressForChainConfig(AppChainConfig cfg) {
    final kind = ChainRules.kindForAppChain(cfg);
    return switch (kind) {
      ChainKind.tron => _tronAddress,
      ChainKind.solana => _solanaAddress,
      ChainKind.xrp => _xrpAddress,
      ChainKind.ton => HdWalletService.tonTestOnlyHeuristic(cfg)
          ? _tonAddressTest
          : _tonAddressMain,
      ChainKind.btc => _btcOwnerAddressFor(cfg),
      ChainKind.doge => _dogeOwnerAddressFor(cfg),
      ChainKind.evm || ChainKind.unknown => _addressHex,
    };
  }

  EthereumAddress? get address =>
      _addressHex == null ? null : EthereumAddress.fromHex(_addressHex!);
  bool get backedUp => _backedUp;
  bool get loading => _loading;
  String? get sendChain => _sendChain;
  /// 首页/转账等：按用户排序，且排除已隐藏币种。
  List<CoinData> get evmCoins => List.unmodifiable(
        _sortedCoins(
          _evmCoins
              .where((c) => c.id.isEmpty || isCoinVisible(c.id))
              .toList(),
        ),
      );

  /// 币种管理页：含隐藏项，顺序与 [evmCoins] 一致规则。
  List<CoinData> get allEvmCoins => List.unmodifiable(_sortedCoins(_evmCoins));

  bool isCoinVisible(String coinId) => !_hiddenCoinIds.contains(coinId);
  Set<String> get hiddenCoinIds => Set.unmodifiable(_hiddenCoinIds);

  void _reconcileCoinOrderWithCoins(List<CoinData> coins) {
    final ids = coins
        .map((c) => c.id)
        .where((id) => id.isNotEmpty)
        .toList();
    final idSet = ids.toSet();
    final next = <String>[];
    for (final id in _coinOrderIds) {
      if (idSet.contains(id)) {
        next.add(id);
      }
    }
    for (final id in ids) {
      if (!next.contains(id)) {
        next.add(id);
      }
    }
    _coinOrderIds = next;
  }

  List<CoinData> _sortedCoins(List<CoinData> coins) {
    if (coins.isEmpty) {
      return const [];
    }
    _reconcileCoinOrderWithCoins(coins);
    final byId = <String, CoinData>{
      for (final c in coins)
        if (c.id.isNotEmpty) c.id: c,
    };
    final ordered = <CoinData>[];
    for (final id in _coinOrderIds) {
      final c = byId[id];
      if (c != null) {
        ordered.add(c);
      }
    }
    for (final c in coins) {
      if (c.id.isEmpty) {
        ordered.add(c);
      } else if (!ordered.any((x) => x.id == c.id)) {
        ordered.add(c);
      }
    }
    return ordered;
  }

  void _assignEvmCoins(List<CoinData> coins) {
    _evmCoins = List<CoinData>.from(coins);
    _reconcileCoinOrderWithCoins(_evmCoins);
  }

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

  /// 自 [backgroundedAtMs] 起是否已在后台超过 [_pinBackgroundGraceDuration]。
  bool _exceededBackgroundPinGrace(int nowMs, int? backgroundedAtMs) {
    if (backgroundedAtMs == null || backgroundedAtMs <= 0) {
      return false;
    }
    return nowMs - backgroundedAtMs > _pinBackgroundGraceDuration.inMilliseconds;
  }

  Future<int?> _readBackgroundAtForActiveWallet() async {
    final wid = _activeWalletId;
    if (wid == null) {
      return null;
    }
    return _storage.readPinBackgroundAtMs(wid);
  }

  Future<void> _clearBackgroundAtForActiveWallet() async {
    final wid = _activeWalletId;
    if (wid == null) {
      return;
    }
    _lastBackgroundedAtMs = null;
    await _storage.clearPinBackgroundAtMs(wid);
  }

  Future<void> _persistBackgroundAtForActiveWallet(int atMs) async {
    final wid = _activeWalletId;
    if (wid == null) {
      return;
    }
    _lastBackgroundedAtMs = atMs;
    try {
      await _storage.writePinBackgroundAtMs(wid, atMs);
    } catch (e, st) {
      debugPrint('writePinBackgroundAtMs: $e\n$st');
    }
  }

  /// 生命周期：进入后台/不可见时调用。
  ///
  /// 需求：切后台时不要显示 PIN，也不要黑屏（App 切换器里保持正常页面快照）。
  /// 因此只标记后台态，用于在 UI 层抑制 UnlockScreen；
  /// 同时**不**在这里把 [_sessionUnlocked] 置为 false，否则 `_HomeShell` 会渲染纯色底导致切换器快照变黑。
  /// 记录进入后台的时刻；回前台时再判断后台是否已超过 30 分钟。
  void onAppBackgrounded() {
    // inactive → paused 会连续回调，仅首次进入后台时写 Keychain，避免并发 write 触发 -25299。
    final enteringBackground = !_appInBackground;
    _appInBackground = true;
    if (enteringBackground && _pinEnabled && _credentials != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _lastBackgroundedAtMs = now;
      unawaited(_persistBackgroundAtForActiveWallet(now));
    }
    notifyListeners();
  }

  /// 生命周期：回到前台时调用。
  ///
  /// 规则：
  /// - 切后台时不展示 PIN、不黑屏（保持切换器快照）
  /// - 回前台时：若本次在后台超过 30 分钟则要求输入 PIN，否则保持解锁
  /// - 一直前台不自动上锁（无定时器）
  Future<void> onAppResumed() async {
    if (!_pinEnabled || _credentials == null) {
      if (_appInBackground) {
        _appInBackground = false;
        notifyListeners();
      }
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final bgAt =
        _lastBackgroundedAtMs ?? await _readBackgroundAtForActiveWallet();
    if (_exceededBackgroundPinGrace(now, bgAt)) {
      _sessionUnlocked = false;
    } else {
      unawaited(_clearBackgroundAtForActiveWallet());
    }
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

  String? _btcOwnerAddressFor(AppChainConfig chainCfg) {
    if (HdWalletService.btcTestnetHeuristic(chainCfg)) {
      return _btcTestnetAddress;
    }
    return _btcMainnetAddress;
  }

  String? _dogeOwnerAddressFor(AppChainConfig chainCfg) {
    if (HdWalletService.dogeTestnetHeuristic(chainCfg)) {
      return _dogeTestnetAddress;
    }
    return _dogeMainnetAddress;
  }

  /// 余额接口返回 null/空列表，或 `cryptos` 未标 `isNative == 1` 时，用链元数据生成至少一条原生占位，避免选网后列表空白。
  List<CoinData> _nativePlaceholderCoinsForChain(
    AppChainConfig chainCfg,
    Map<String, AppSymbolQuote> quotes,
    int? chainIdInt,
  ) {
    final chainParam = chainCfg.walletApiChainQuery;
    final coins = <CoinData>[];
    final seen = <String>{};
    Iterable<AppChainCrypto> natives =
        chainCfg.cryptos.where((c) => c.isNative == 1);
    if (natives.isEmpty && chainCfg.cryptos.length == 1) {
      natives = chainCfg.cryptos;
    }
    void addOne(String symRaw, String? nameFromMeta) {
      final u = symRaw.trim().toUpperCase();
      if (u.isEmpty) {
        return;
      }
      final key = '${chainCfg.backendStableSegment}_$u';
      if (!seen.add(key)) {
        return;
      }
      final pair = AppPriceService.usdtPairKeyForSymbol(u);
      final q = AppPriceService.resolveQuote(u, quotes[pair]);
      coins.add(
        CoinData(
          id: chainCfg.coinPrimaryId(u),
          symbol: u,
          name: (nameFromMeta ?? '').trim().isNotEmpty
              ? nameFromMeta!.trim()
              : u,
          icon: '',
          network: chainCfg.chainName,
          chainId: chainIdInt,
          walletApiChainQuery: chainParam,
          txUrlPrefix: chainCfg.txUrlPrefix,
          addressUrlPrefix: chainCfg.addressUrlPrefix,
          price: q.price,
          priceChange24h: q.change24h,
          balance: 0.0,
          balanceUSD: 0.0,
        ),
      );
    }

    for (final c in natives) {
      final sym = c.crypto.trim();
      if (sym.isEmpty) {
        continue;
      }
      addOne(sym, c.cryptoName);
    }
    if (coins.isEmpty) {
      final fb = chainCfg.symbol.trim();
      if (fb.isNotEmpty) {
        final cn = chainCfg.chainName.trim();
        addOne(fb, cn.isNotEmpty ? cn : null);
      }
    }
    return coins;
  }

  /// 该链用于余额查询的地址；无则 `null` 或空串。
  String? _ownerAddressStringForChain(AppChainConfig chainCfg) {
    final kind = ChainRules.kindForAppChain(chainCfg);
    final owner = switch (kind) {
      ChainKind.tron => _tronAddress ?? '',
      ChainKind.solana => _solanaAddress ?? '',
      ChainKind.xrp => _xrpAddress ?? '',
      ChainKind.ton => HdWalletService.tonTestOnlyHeuristic(chainCfg)
          ? (_tonAddressTest ?? '')
          : (_tonAddressMain ?? ''),
      ChainKind.btc => _btcOwnerAddressFor(chainCfg) ?? '',
      ChainKind.doge => _dogeOwnerAddressFor(chainCfg) ?? '',
      ChainKind.evm || ChainKind.unknown =>
        _credentials?.address.hex ?? _addressHex ?? '',
    };
    final t = owner.trim();
    return t.isEmpty ? null : t;
  }

  bool _chainsListEquivalent(
    List<AppChainConfig> a,
    List<AppChainConfig> b,
  ) {
    if (a.length != b.length) {
      return false;
    }
    String key(AppChainConfig c) =>
        (c.chainCode ?? c.chainId).trim().toUpperCase();
    final ak = a.map(key).toList()..sort();
    final bk = b.map(key).toList()..sort();
    for (var i = 0; i < ak.length; i++) {
      if (ak[i] != bk[i]) {
        return false;
      }
    }
    return true;
  }

  /// 网络拉取链列表；有缓存时可在后台执行，更新后可选再刷余额。
  Future<void> _loadBackendChainsFromNetwork({
    required bool refreshBalancesIfChanged,
  }) async {
    HomeRefreshProfiler.mark('before GET /api/app/chains (network)');
    final list = await _chainsService.fetchChains();
    HomeRefreshProfiler.mark(
      'GET /api/app/chains network (${list.length} chains)',
    );
    if (list.isNotEmpty) {
      final changed = !_chainsListEquivalent(_backendChains, list);
      _backendChains = list;
      unawaited(_localCache?.putChains(list));
      _ensureSendChainDefault();
      if (changed) {
        notifyListeners();
      }
      if (changed &&
          refreshBalancesIfChanged &&
          _initReady &&
          _credentials != null &&
          (!_pinEnabled || _sessionUnlocked)) {
        unawaited(refreshBalances());
      }
      if (kDebugMode && _backendChains.isNotEmpty) {
        debugPrint('WalletController: backend chains ${_backendChains.length}');
      }
    } else if (_backendChains.isEmpty) {
      final cached = await _localCache?.getChains();
      if (cached != null && cached.isNotEmpty) {
        _backendChains = cached;
        _ensureSendChainDefault();
        notifyListeners();
      }
    }
  }

  void _applyDerivedAddressSnapshot(DerivedAddressSnapshot snap) {
    _addressHex = snap.addressHex;
    _tronAddress = snap.tronAddress;
    _solanaAddress = snap.solanaAddress;
    _xrpAddress = snap.xrpAddress;
    _tonAddressMain = snap.tonAddressMain;
    _tonAddressTest = snap.tonAddressTest;
    _btcMainnetAddress = snap.btcMainnetAddress;
    _btcTestnetAddress = snap.btcTestnetAddress;
    _dogeMainnetAddress = snap.dogeMainnetAddress;
    _dogeTestnetAddress = snap.dogeTestnetAddress;
  }

  DerivedAddressSnapshot _derivedAddressSnapshotFromState() {
    return DerivedAddressSnapshot(
      addressHex: _addressHex ?? '',
      tronAddress: _tronAddress,
      solanaAddress: _solanaAddress,
      xrpAddress: _xrpAddress,
      tonAddressMain: _tonAddressMain,
      tonAddressTest: _tonAddressTest,
      btcMainnetAddress: _btcMainnetAddress,
      btcTestnetAddress: _btcTestnetAddress,
      dogeMainnetAddress: _dogeMainnetAddress,
      dogeTestnetAddress: _dogeTestnetAddress,
    );
  }

  /// 拉取行情并输出 `[HomeRefresh] POST /api/app/price/all` 耗时；失败时用本地缓存。
  Future<Map<String, AppSymbolQuote>> _fetchPriceQuotesForHomeRefresh() async {
    HomeRefreshProfiler.mark('before POST /api/app/price/all');
    final sw = Stopwatch()..start();
    var quotes = await _appPriceService.fetchAllPrices();
    sw.stop();
    var usedCache = false;
    final requestFailed = quotes.isEmpty;
    if (quotes.isEmpty) {
      final cachedQ = await _localCache?.getPriceQuotes();
      if (cachedQ != null && cachedQ.isNotEmpty) {
        quotes = cachedQ;
        usedCache = true;
      }
    }
    HomeRefreshProfiler.logPriceFetchDone(
      wallMs: sw.elapsedMilliseconds,
      pairCount: quotes.length,
      usedCacheFallback: usedCache,
      requestFailed: requestFailed && !usedCache,
    );
    return quotes;
  }

  List<BatchBalanceRequestItem> _batchBalanceRequestItems(
    Iterable<AppChainConfig> chains,
  ) {
    final items = <BatchBalanceRequestItem>[];
    for (final chainCfg in chains) {
      final chainParam = chainCfg.walletApiChainQuery.trim();
      if (chainParam.isEmpty) {
        continue;
      }
      final owner = _ownerAddressStringForChain(chainCfg);
      if (owner == null) {
        continue;
      }
      items.add(
        BatchBalanceRequestItem(
          address: owner,
          chain: chainParam,
        ),
      );
    }
    return items;
  }

  BatchWalletBalanceResult? _batchResultForChain(
    AppChainConfig chainCfg,
    List<BatchWalletBalanceResult> results,
  ) {
    final want = chainCfg.walletApiChainQuery.trim().toUpperCase();
    for (final r in results) {
      if ((r.chain ?? '').trim().toUpperCase() == want) {
        return r;
      }
    }
    return null;
  }

  List<CoinData> _coinDataFromBalanceEntries(
    AppChainConfig chainCfg,
    List<WalletBalanceEntry> remote,
    Map<String, AppSymbolQuote> quotes,
  ) {
    final chainParam = chainCfg.walletApiChainQuery;
    final kind = ChainRules.kindForAppChain(chainCfg);
    final chainIdInt =
        kind == ChainKind.evm ? int.tryParse(chainCfg.chainId) : null;
    final coins = <CoinData>[];
    final seen = <String>{};
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
      final bal = row.balance;
      coins.add(
        CoinData(
          id: chainCfg.coinPrimaryId(sym),
          symbol: sym.toUpperCase(),
          name: meta?.cryptoName ?? sym.toUpperCase(),
          icon: '',
          network: chainCfg.chainName,
          chainId: chainIdInt,
          walletApiChainQuery: chainParam,
          txUrlPrefix: chainCfg.txUrlPrefix,
          addressUrlPrefix: chainCfg.addressUrlPrefix,
          price: q.price,
          priceChange24h: q.change24h,
          balance: bal,
          balanceUSD: bal * q.price,
        ),
      );
    }
    return coins;
  }

  /// 将批量接口单项或失败结果转为 [CoinData] 列表；`null` 表示该链应跳过。
  List<CoinData>? _coinsForChainFromBatchRow(
    AppChainConfig chainCfg,
    BatchWalletBalanceResult? batchRow,
    Map<String, AppSymbolQuote> quotes,
  ) {
    if (batchRow != null && batchRow.success && batchRow.balances.isNotEmpty) {
      return _coinDataFromBalanceEntries(chainCfg, batchRow.balances, quotes);
    }
    final kind = ChainRules.kindForAppChain(chainCfg);
    final owner = _ownerAddressStringForChain(chainCfg);
    if (owner == null) {
      if (kind == ChainKind.ton) {
        return _nativePlaceholderCoinsForChain(chainCfg, quotes, null);
      }
      return null;
    }
    final chainIdInt =
        kind == ChainKind.evm ? int.tryParse(chainCfg.chainId) : null;
    return _nativePlaceholderCoinsForChain(chainCfg, quotes, chainIdInt);
  }

  /// 仅请求 `POST /api/app/wallet/balances/batch`（可与行情并行）。
  Future<List<BatchWalletBalanceResult>?> _fetchBalancesBatchResults(
    List<AppChainConfig> backendChains,
  ) async {
    final items = _batchBalanceRequestItems(backendChains);
    if (items.isEmpty) {
      return null;
    }
    HomeRefreshProfiler.mark(
      'before POST /api/app/wallet/balances/batch (${items.length} items)',
    );
    final sw = Stopwatch()..start();
    final batchResults =
        await _walletBalanceService.fetchBalancesBatch(items: items);
    sw.stop();
    if (batchResults == null) {
      if (kDebugMode) {
        debugPrint('[HomeRefresh] POST balances/batch failed, will fallback');
      }
      return null;
    }
    final balanceRowCount = batchResults.fold<int>(
      0,
      (n, r) => n + r.balances.length,
    );
    HomeRefreshProfiler.logBalanceBatchDone(
      wallMs: sw.elapsedMilliseconds,
      chainCount: batchResults.length,
      perChainMs: {'POST balances/batch': sw.elapsedMilliseconds},
      mode: 'POST balances/batch',
      balanceRowCount: balanceRowCount,
    );
    if (kDebugMode) {
      for (final r in batchResults) {
        debugPrint(
          '[HomeRefresh] batch chain=${r.chain} success=${r.success} '
          'n=${r.balances.length}'
          '${r.errorMessage != null ? " err=${r.errorMessage}" : ""}',
        );
      }
    }
    return batchResults;
  }

  Future<({List<CoinData> coins, bool anyOk})> _mergeBatchBalanceResults(
    List<AppChainConfig> backendChains,
    List<BatchWalletBalanceResult>? batchResults,
    Map<String, AppSymbolQuote> quotes,
  ) async {
    if (batchResults == null) {
      return (coins: <CoinData>[], anyOk: false);
    }
    final coins = <CoinData>[];
    final seen = <String>{};
    var anyOk = false;
    for (final chainCfg in backendChains) {
      final row = _batchResultForChain(chainCfg, batchResults);
      final partial = _coinsForChainFromBatchRow(chainCfg, row, quotes);
      if (partial == null) {
        continue;
      }
      if (row != null && row.success && row.balances.isNotEmpty) {
        anyOk = true;
      } else if (partial.isNotEmpty) {
        anyOk = true;
      }
      for (final cd in partial) {
        final key =
            '${chainCfg.backendStableSegment}_${cd.symbol.toUpperCase()}';
        if (!seen.add(key)) {
          continue;
        }
        coins.add(cd);
      }
    }
    return (coins: coins, anyOk: anyOk);
  }

  Future<({List<CoinData> coins, bool anyOk})> _refreshCoinsViaPerChainBalance(
    List<AppChainConfig> backendChains,
    Map<String, AppSymbolQuote> quotes,
  ) async {
    final coins = <CoinData>[];
    final seen = <String>{};
    var anyOk = false;
    HomeRefreshProfiler.mark(
      'before per-chain GET balance (${backendChains.length} chains, parallel)',
    );
    final balanceBatchSw = Stopwatch()..start();
    final perChainMs = <String, int>{};
    final chainResults = await Future.wait(
      backendChains.map((chainCfg) async {
        final q = chainCfg.walletApiChainQuery;
        final sw = Stopwatch()..start();
        final partial = await _loadCoinsForChainConfig(chainCfg, quotes);
        perChainMs[q] = sw.elapsedMilliseconds;
        if (kDebugMode) {
          debugPrint(
            '[HomeRefresh] GET /api/app/wallet/balance?chain=$q '
            '${sw.elapsedMilliseconds}ms '
            '${partial == null ? 'skip' : '${partial.length} coins'}',
          );
        }
        return (chainCfg, partial);
      }),
    );
    balanceBatchSw.stop();
    HomeRefreshProfiler.logBalanceBatchDone(
      wallMs: balanceBatchSw.elapsedMilliseconds,
      chainCount: backendChains.length,
      perChainMs: perChainMs,
      mode: 'per-chain GET balance',
    );
    for (final entry in chainResults) {
      final chainCfg = entry.$1;
      final partial = entry.$2;
      if (partial == null) {
        continue;
      }
      anyOk = true;
      for (final cd in partial) {
        final key =
            '${chainCfg.backendStableSegment}_${cd.symbol.toUpperCase()}';
        if (!seen.add(key)) {
          continue;
        }
        coins.add(cd);
      }
    }
    return (coins: coins, anyOk: anyOk);
  }

  /// 拉取单条链的余额并组装 [CoinData]；`null` 表示无主地址（全量刷新时跳过该链；单链刷新时保留旧数据）。
  /// 接口失败或返回空列表时仍可能返回仅含占位行的非空列表，以便首页能展示该链主币。
  Future<List<CoinData>?> _loadCoinsForChainConfig(
    AppChainConfig chainCfg,
    Map<String, AppSymbolQuote> quotes,
  ) async {
    if (_credentials == null) {
      return null;
    }
    final chainParam = chainCfg.walletApiChainQuery;
    final kind = ChainRules.kindForAppChain(chainCfg);
    final ownerAddress = _ownerAddressStringForChain(chainCfg) ?? '';
    if (ownerAddress.isEmpty) {
      // TON 地址推导失败或未就绪时仍展示占位资产，避免首页完全看不到 TON；详情/收款处再提示地址未就绪。
      if (kind == ChainKind.ton) {
        return _nativePlaceholderCoinsForChain(chainCfg, quotes, null);
      }
      return null;
    }
    if (kDebugMode) {
      debugPrint(
        'refreshBalances: chain=$chainParam kind=$kind address=$ownerAddress',
      );
    }
    final List<WalletBalanceEntry>? remote;
    if (kind == ChainKind.solana ||
        kind == ChainKind.xrp ||
        kind == ChainKind.ton) {
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
            coin: crypto,
          ),
        ),
      );
      // 某一 crypto 余额接口失败时不应拖垮整条链；全部失败时走下方「仅原生、余额 0」分支。
      final byCrypto = <String, WalletBalanceEntry>{};
      for (final p in parts) {
        if (p == null) continue;
        for (final row in p) {
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
      );
    }
    final chainIdInt =
        kind == ChainKind.evm ? int.tryParse(chainCfg.chainId) : null;
    if (remote != null && remote.isNotEmpty) {
      return _coinDataFromBalanceEntries(chainCfg, remote, quotes);
    }
    return _nativePlaceholderCoinsForChain(chainCfg, quotes, chainIdInt);
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
      final quotes = await _fetchPriceQuotesForHomeRefresh();
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
      _assignEvmCoins([...others, ...replacement]);
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

  bool _canQueryBalances() {
    for (final c in _activeBackendChains()) {
      if (_ownerAddressStringForChain(c) != null) {
        return true;
      }
    }
    return _credentials != null;
  }

  Future<void> init() async {
    _initReady = false;
    notifyListeners();
    // 让首帧 loading 先绘制，再执行后续 I/O。
    await Future<void>.delayed(Duration.zero);

    var hadChainsCache = false;
    try {
      if (kDebugMode) {
        debugPrint('WalletController.init: start');
      }
      HomeRefreshProfiler.begin('init');
      HomeRefreshProfiler.mark('before chains (cache)');
      final cachedChains = await _localCache?.getChains();
      hadChainsCache = cachedChains != null && cachedChains.isNotEmpty;
      if (hadChainsCache) {
        _backendChains = cachedChains;
        HomeRefreshProfiler.mark(
          'chains from cache (${_backendChains.length})',
        );
        _ensureSendChainDefault();
      }
      unawaited(
        _loadBackendChainsFromNetwork(
          refreshBalancesIfChanged: hadChainsCache,
        ),
      );
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
        _coinOrderIds =
            await _storage.readCoinOrderForWallet(_activeWalletId!);
      } else {
        _hiddenCoinIds = <String>{};
        _coinOrderIds = [];
      }

      // 冷启动优先用 Drift 快照先画首页资产列表，接口返回后再更新。
      final wid = _activeWalletId;
      if (wid != null) {
        try {
          final snap = await _localCache?.getEvmCoinsForWallet(wid);
          if (snap != null && snap.isNotEmpty) {
            _assignEvmCoins(snap);
            _ensureSendChainDefault();
          }
        } catch (_) {
          // 缓存读失败不影响正常启动流程
        }
      }

      if (_pinEnabled) {
        _sessionUnlocked = false;
      } else {
        _sessionUnlocked = true;
      }
    } catch (e, st) {
      debugPrint('WalletController.init failed: $e\n$st');
    } finally {
      HomeRefreshProfiler.end('init');
      _initReady = true;
      notifyListeners();
      if (kDebugMode) {
        debugPrint('WalletController.init: shell ready');
      }
    }

    var startedEarlyBalanceRefresh = false;
    try {
      if (_activeWalletId != null) {
        if (kDebugMode) {
          debugPrint('WalletController.init: load credentials (background)');
        }
        HomeRefreshProfiler.mark('before load credentials');
        startedEarlyBalanceRefresh =
            await _loadCredentialsFromActiveMnemonic(
          overlapBalanceRefresh: hadChainsCache,
        );
        HomeRefreshProfiler.mark('credentials loaded');
        if (_pinEnabled && _credentials != null) {
          _lastBackgroundedAtMs = null;
          final wid = _activeWalletId;
          if (wid != null) {
            unawaited(_storage.clearPinBackgroundAtMs(wid));
          }
        }
      }
    } catch (e, st) {
      debugPrint('WalletController.init credentials failed: $e\n$st');
    }
    if (kDebugMode) {
      debugPrint('WalletController.init: done');
    }
    // 已启用 PIN 且未解锁时不要在后台拉余额：会多次 notifyListeners，主线程在解锁层下仍重建整个 MainTabs。
    if (_canQueryBalances() &&
        (!_pinEnabled || _sessionUnlocked) &&
        !startedEarlyBalanceRefresh) {
      unawaited(refreshBalances());
    }
  }

  /// 历史版本 [markBackedUp] 只写了 `wallet_backed_up__` 未写钱包列表 JSON，重启后列表里仍为未备份。
  /// 启动时若独立 key 为已备份则合并进列表并持久化。
  Future<void> _reconcileBackedUpFromLegacyKeys() async {
    final next = await Future.wait(
      _wallets.map((w) async {
        if (!w.backedUp && await _storage.readBackedUpForWallet(w.id)) {
          return w.copyWith(backedUp: true);
        }
        return w;
      }),
    );
    var dirty = false;
    for (var i = 0; i < _wallets.length; i++) {
      if (_wallets[i].backedUp != next[i].backedUp) {
        dirty = true;
        break;
      }
    }
    if (dirty) {
      _wallets = next;
      await _storage.writeWalletList(_wallets);
    }
  }

  void _applyDerivedKeysResult(WalletDerivedKeysResult result) {
    _credentials = EthPrivateKey(result.evmPrivateKey);
    _addressHex = result.addressHex;
    _tronPrivateKey = result.tronPrivateKey;
    _tronAddress = result.tronAddress;
    _solanaAddress = result.solanaAddress;
    _xrpAddress = result.xrpAddress;
    _tonAddressMain = result.tonAddressMain;
    _tonAddressTest = result.tonAddressTest;
    _btcMainnetAddress = result.btcMainnetAddress;
    _btcTestnetAddress = result.btcTestnetAddress;
    _dogeMainnetAddress = result.dogeMainnetAddress;
    _dogeTestnetAddress = result.dogeTestnetAddress;
  }

  Future<void> _applyDerivedKeysFromMnemonic(String m) async {
    final result = await deriveWalletKeysInBackground(m);
    _applyDerivedKeysResult(result);
  }

  /// 返回是否在派生完成前已用地址缓存发起余额刷新。
  Future<bool> _loadCredentialsFromActiveMnemonic({
    bool overlapBalanceRefresh = false,
  }) async {
    _credentials = null;
    _addressHex = null;
    _tronPrivateKey = null;
    _tronAddress = null;
    _solanaAddress = null;
    _xrpAddress = null;
    _tonAddressMain = null;
    _tonAddressTest = null;
    _btcMainnetAddress = null;
    _btcTestnetAddress = null;
    _dogeMainnetAddress = null;
    _dogeTestnetAddress = null;
    _backedUp = false;
    final id = _activeWalletId;
    if (id == null) {
      return false;
    }
    final m = await _storage.readMnemonicForWallet(id);
    if (m == null || m.isEmpty) {
      return false;
    }

    final addrSnap = await _localCache?.getDerivedAddresses(id);
    final hadAddrSnap = addrSnap != null;
    if (hadAddrSnap) {
      _applyDerivedAddressSnapshot(addrSnap);
    }

    var startedEarlyRefresh = false;
    if (overlapBalanceRefresh &&
        hadAddrSnap &&
        (!_pinEnabled || _sessionUnlocked) &&
        _canQueryBalances()) {
      if (kDebugMode) {
        debugPrint(
          'WalletController: overlap refreshBalances during key derive',
        );
      }
      unawaited(refreshBalances());
      startedEarlyRefresh = true;
    }

    try {
      await _applyDerivedKeysFromMnemonic(m);
      final idx = _wallets.indexWhere((w) => w.id == id);
      _backedUp = idx >= 0
          ? _wallets[idx].backedUp
          : await _storage.readBackedUpForWallet(id);
      unawaited(
        _localCache?.putDerivedAddresses(
          id,
          _derivedAddressSnapshotFromState(),
        ),
      );
      notifyListeners();
    } catch (e, st) {
      debugPrint('Wallet init failed: $e\n$st');
      _credentials = null;
      _addressHex = null;
      _tronPrivateKey = null;
      _tronAddress = null;
      _solanaAddress = null;
      _xrpAddress = null;
      _tonAddressMain = null;
      _tonAddressTest = null;
      _btcMainnetAddress = null;
      _btcTestnetAddress = null;
      _dogeMainnetAddress = null;
      _dogeTestnetAddress = null;
      return false;
    }
    return startedEarlyRefresh;
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
      _tonAddressMain = null;
      _tonAddressTest = null;
      _btcMainnetAddress = null;
      _btcTestnetAddress = null;
    }
    _backedUp = false;
    _sessionUnlocked = true;
    if (_pinEnabled) {
      unawaited(_clearBackgroundAtForActiveWallet());
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
      _tonAddressMain = null;
      _tonAddressTest = null;
      _btcMainnetAddress = null;
      _btcTestnetAddress = null;
    }
    _backedUp = false;
    _sessionUnlocked = true;
    if (_pinEnabled) {
      unawaited(_clearBackgroundAtForActiveWallet());
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
    _coinOrderIds = await _storage.readCoinOrderForWallet(id);
    await _loadCredentialsFromActiveMnemonic();
    _lastBackgroundedAtMs = null;
    // 切换钱包不重新要求 PIN；清掉目标钱包旧的「进后台」记录，避免误用历史时间戳。
    if (_pinEnabled) {
      unawaited(_clearBackgroundAtForActiveWallet());
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

  Future<void> updateCoinOrder(List<String> orderedIds) async {
    final id = _activeWalletId;
    if (id == null) {
      return;
    }
    _coinOrderIds = List<String>.from(orderedIds);
    _reconcileCoinOrderWithCoins(_evmCoins);
    notifyListeners();
    await _storage.writeCoinOrderForWallet(id, _coinOrderIds);
  }

  Future<void> moveCoinToTop(String coinId) async {
    if (coinId.isEmpty) {
      return;
    }
    final next = List<String>.from(_coinOrderIds);
    next.remove(coinId);
    next.insert(0, coinId);
    await updateCoinOrder(next);
  }

  Future<void> reorderManagedCoins(int oldIndex, int newIndex) async {
    final items = List<CoinData>.from(allEvmCoins);
    if (oldIndex < 0 ||
        oldIndex >= items.length ||
        newIndex < 0 ||
        newIndex > items.length) {
      return;
    }
    var target = newIndex;
    if (target > oldIndex) {
      target -= 1;
    }
    final item = items.removeAt(oldIndex);
    items.insert(target, item);
    await updateCoinOrder(
      items.map((c) => c.id).where((id) => id.isNotEmpty).toList(),
    );
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
        _tonAddressMain = null;
        _tonAddressTest = null;
        _btcMainnetAddress = null;
        _btcTestnetAddress = null;
        _backedUp = false;
        _assignEvmCoins([]);
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

  /// 根据助记词推导该钱包的 TON 友好地址（主网 / 测试网由 [testOnly] 决定），不切换当前钱包。
  Future<String?> readTonAddressForWallet(
    String walletId, {
    required bool testOnly,
  }) async {
    final m = await _storage.readMnemonicForWallet(walletId);
    if (m == null || m.isEmpty) {
      return null;
    }
    try {
      return await HdWalletService.tonFriendlyAddressFromMnemonic(
        m,
        testOnly: testOnly,
      );
    } catch (e, st) {
      debugPrint('readTonAddressForWallet: $e\n$st');
      return null;
    }
  }

  /// 根据助记词推导该钱包的 BTC Native SegWit（BIP84）地址，不切换当前钱包。
  Future<String?> readBtcAddressForWallet(
    String walletId, {
    required bool testnet,
  }) async {
    final m = await _storage.readMnemonicForWallet(walletId);
    if (m == null || m.isEmpty) {
      return null;
    }
    try {
      return HdWalletService.btcP2wpkhAddressFromMnemonic(m, testnet: testnet);
    } catch (e, st) {
      debugPrint('readBtcAddressForWallet: $e\n$st');
      return null;
    }
  }

  /// 根据助记词推导该钱包的 Dogecoin P2PKH（BIP44 coin type 3）地址。
  Future<String?> readDogeAddressForWallet(
    String walletId, {
    required bool testnet,
  }) async {
    final m = await _storage.readMnemonicForWallet(walletId);
    if (m == null || m.isEmpty) {
      return null;
    }
    try {
      return HdWalletService.dogeP2pkhAddressFromMnemonic(m, testnet: testnet);
    } catch (e, st) {
      debugPrint('readDogeAddressForWallet: $e\n$st');
      return null;
    }
  }

  Future<PinVerifyResult> verifyTransactionPin(String pin) =>
      _storage.verifyPin(pin);

  Future<PinVerifyResult> unlockSession(String pin) async {
    final r = await _storage.verifyPin(pin);
    if (r.ok) {
      _sessionUnlocked = true;
      unawaited(_clearBackgroundAtForActiveWallet());
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

  /// 广播成功后调用：失效对应交易历史缓存并通知 UI 重拉列表。
  Future<void> notifyTransferCompleted({
    required String chainParam,
    required String coinSymbol,
  }) async {
    _txHistoryRefreshTick++;
    final cache = _localCache;
    final q = chainParam.trim();
    if (cache != null && q.isNotEmpty) {
      AppChainConfig? cfg;
      for (final c in _activeBackendChains()) {
        if (c.walletApiChainQuery == q) {
          cfg = c;
          break;
        }
      }
      if (cfg != null) {
        final owner = ownerAddressForChainConfig(cfg);
        if (owner != null && owner.trim().isNotEmpty) {
          final kind = ChainRules.kindForAppChain(cfg);
          final addr = ChainRules.formatAddressForUi(kind, owner);
          final scope = cache.transactionScopeKey(addr, q, coinSymbol);
          try {
            await cache.clearTransactionHistory(scope);
          } catch (e) {
            debugPrint('clearTransactionHistory: $e');
          }
        }
      }
    }
    notifyListeners();
  }

  Future<void> refreshBalances() async {
    if (!_canQueryBalances()) {
      return;
    }
    _loading = true;
    notifyListeners();
    HomeRefreshProfiler.begin('refreshBalances');
    try {
      final backendChains = _activeBackendChains().toList();
      HomeRefreshProfiler.mark('parallel: price + balances/batch');

      late final Map<String, AppSymbolQuote> quotes;
      late ({List<CoinData> coins, bool anyOk}) outcome;
      var anyBalanceRequestOk = backendChains.isEmpty;

      if (backendChains.isEmpty) {
        quotes = await _fetchPriceQuotesForHomeRefresh();
        outcome = (coins: <CoinData>[], anyOk: false);
      } else {
        final parallel = await Future.wait<Object?>([
          _fetchPriceQuotesForHomeRefresh(),
          _fetchBalancesBatchResults(backendChains),
        ]);
        quotes = parallel[0]! as Map<String, AppSymbolQuote>;
        final batchResults =
            parallel[1] as List<BatchWalletBalanceResult>?;
        outcome = await _mergeBatchBalanceResults(
          backendChains,
          batchResults,
          quotes,
        );
      }

      final coins = <CoinData>[];
      if (backendChains.isNotEmpty) {
        if (!outcome.anyOk) {
          if (kDebugMode) {
            debugPrint(
              '[HomeRefresh] balances/batch unavailable, fallback per-chain',
            );
          }
          outcome =
              await _refreshCoinsViaPerChainBalance(backendChains, quotes);
        }
        coins.addAll(outcome.coins);
        anyBalanceRequestOk = outcome.anyOk;
        if (kDebugMode) {
          HomeRefreshProfiler.mark('balance list merged (${coins.length} coins)');
        }
      }
      // 无网时各链常返回 null（非抛错），下面会造出全 0 列表；用 Drift 上次快照，避免全 0 占屏、勿把好缓存写坏
      if (backendChains.isNotEmpty && !anyBalanceRequestOk) {
        final wid = _activeWalletId;
        if (wid != null) {
          final snap = await _localCache?.getEvmCoinsForWallet(wid);
          if (snap != null && snap.isNotEmpty) {
            _assignEvmCoins(snap);
            _ensureSendChainDefault();
            if (quotes.isNotEmpty) {
              unawaited(_localCache?.putPriceQuotes(quotes));
            }
            return;
          }
        }
      }
      _assignEvmCoins(coins);
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
          _assignEvmCoins(snap);
        }
      }
    } finally {
      HomeRefreshProfiler.end('refreshBalances');
      _loading = false;
      notifyListeners();
    }
  }

  /// 首页下拉刷新：重读钱包列表与当前选中钱包，并刷新链上余额与行情。
  Future<void> refreshWalletHome() async {
    HomeRefreshProfiler.begin('pullToRefresh');
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
      HomeRefreshProfiler.mark('before load credentials');
      await _loadCredentialsFromActiveMnemonic();
      HomeRefreshProfiler.mark('credentials loaded');
      if (_credentials != null) {
        await refreshBalances();
      } else {
        _assignEvmCoins([]);
        notifyListeners();
      }
    } catch (e, st) {
      debugPrint('refreshWalletHome: $e\n$st');
      notifyListeners();
    } finally {
      HomeRefreshProfiler.end('pullToRefresh');
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
    final raw = BtcBackendTransfer.parseBroadcastTxHash(data);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final t = WalletTransactionService.normalizeTxHashForApi(raw);
    return t.isEmpty ? null : t;
  }

  Future<String> _signBroadcastUtxoTransfer({
    required AppChainConfig cfg,
    required String chain,
    required String coin,
    required String toAddress,
    required num amount,
    String? gasPriceType,
    required bool testnet,
    required String? ownerMainnet,
    required String? ownerTestnet,
    required String derivationPathMainnet,
    required String derivationPathTestnet,
    required String notReadyLabel,
    required bool doge,
  }) async {
    final wid = _activeWalletId;
    if (wid == null) {
      throw StateError('未选择钱包');
    }
    final phrase = await _storage.readMnemonicForWallet(wid);
    if (phrase == null || phrase.trim().isEmpty) {
      throw StateError('无法读取助记词');
    }
    final owner = testnet ? (ownerTestnet ?? '') : (ownerMainnet ?? '');
    if (owner.isEmpty) {
      throw StateError('$notReadyLabel 地址未就绪');
    }
    final create = await _transferApi.createTransaction(
      chain: chain,
      coin: coin,
      ownerAddress: owner,
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
    var data = BtcBackendTransfer.normalizeCreateTransactionPayload(create['data']);
    if (BtcBackendTransfer.needsInputFeeHint(data, doge: doge)) {
      final est = await WalletEstimateGasService().estimateGasPreferV2(
        chain: chain,
        coin: coin,
        ownerAddress: owner,
        toAddress: toAddress,
        amount: amount,
        requireGasLimit: false,
      );
      double? fee = WalletEstimateGasService.parseNetworkFee(est);
      if (fee == null) {
        final txSize = WalletEstimateGasService.parseTxSize(est) ??
            BtcBackendTransfer.parseTxVsizeFromDecoded(data);
        if (txSize != null) {
          final quote =
              await WalletGasPriceService().fetchBtcFeeQuote(chain: chain);
          fee = WalletEstimateGasService.computeUtxoFeeCoin(
            txSize: txSize,
            quote: quote ?? kBtcFeeQuoteFallbackSatPerVbyte,
          );
        }
      }
      if (fee != null) {
        // 费率单位误判时 fee 会极小（如 1e-8），改走余额兜底。
        if (doge && fee < 1e-6) {
          fee = null;
        } else {
          data = {...data, 'fee': fee};
          if (kDebugMode) {
            debugPrint('$notReadyLabel createTransaction: 推断 fee=$fee');
          }
        }
      }
      if (fee == null &&
          BtcBackendTransfer.needsInputFeeHint(data, doge: doge)) {
        final bals = await _walletBalanceService.fetchBalances(
          address: owner,
          chain: chain,
          coin: coin,
        );
        final bal = bals?.isNotEmpty == true ? bals!.first.balance : null;
        if (bal != null && bal > 0) {
          data = {...data, 'totalInput': bal};
          if (kDebugMode) {
            debugPrint('$notReadyLabel createTransaction: 用余额作 totalInput=$bal');
          }
        } else if (kDebugMode) {
          debugPrint('$notReadyLabel createTransaction: 无法推断 fee（缺 txSize/费率）');
        }
      }
    }
    if (kDebugMode) {
      debugPrint(
        '$notReadyLabel createTransaction.data keys: ${data.keys.join(", ")}',
      );
    }
    final path =
        testnet ? derivationPathTestnet : derivationPathMainnet;
    final pk = HdWalletService.btcEcprivateFromMnemonicPath(phrase, path);
    final signedHex = BtcBackendTransfer.signCreateTransactionData(
      data: data,
      ownerPrivateKey: pk,
      expectedOwnerAddress: owner,
      testnet: testnet,
      doge: doge,
    );

    if (doge && kDogeSkipBroadcastForBackendTest) {
      final broadcastPayload = <String, dynamic>{
        'chain': chain,
        'coin': coin,
        'data': signedHex,
      };
      debugPrint('');
      debugPrint('======== $notReadyLabel [BackendTest] broadcastTransaction ========');
      debugPrint('POST /api/app/wallet/broadcastTransaction');
      debugPrint(const JsonEncoder.withIndent('  ').convert(broadcastPayload));
      debugPrint(
        '$notReadyLabel [BackendTest] data: ${signedHex.length} hex chars, '
        '${signedHex.length ~/ 2} bytes',
      );
      debugPrint('======== 未调用广播接口（kDogeSkipBroadcastForBackendTest=true） ========');
      debugPrint('');
      throw StateError(
        '$notReadyLabel 联调模式：已签名未广播，请将控制台 [BackendTest] 中的 JSON 发给后端',
      );
    }

    final broad = await _transferApi.broadcastTransaction(
      chain: chain,
      coin: coin,
      data: signedHex,
    );
    if (broad == null) {
      throw StateError('broadcastTransaction 无响应');
    }
    if (broad['code'] != 0) {
      final msg = broad['message']?.toString() ?? 'broadcastTransaction 失败';
      throw StateError(msg);
    }
    final h = _readTxHashFromBroadcast(broad['data']);
    return h ?? signedHex;
  }

  /// 波场能量租赁：preorder → 本地签名 → confirmOrder。
  Future<TronResourceConfirmVo> rentTronEnergy(
    TronResourcePreOrderDto dto,
  ) async {
    final pk = _tronPrivateKey;
    if (pk == null || _tronAddress == null || _tronAddress!.isEmpty) {
      throw StateError('Tron 钱包未初始化');
    }
    final pre = await _tronResourceService.preorder(dto);
    final signData =
        TronTransactionSigner.extractRawDataHex(pre.transaction) != null
            ? pre.transaction
            : <String, dynamic>{'transaction': pre.transaction};
    final signed = TronTransactionSigner.signApiData(signData, pk);
    return _tronResourceService.confirmOrder(
      orderId: pre.orderId,
      signedData: signed.signedJson,
    );
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
      final wid = _activeWalletId;
      if (wid == null) {
        throw StateError('未选择钱包');
      }
      final phrase = await _storage.readMnemonicForWallet(wid);
      if (phrase == null || phrase.trim().isEmpty) {
        throw StateError('无法读取助记词');
      }
      final owner = _xrpAddress;
      if (owner == null || owner.isEmpty) {
        throw StateError('XRP 地址未就绪');
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
      final pk = XrpBackendTransfer.privateKeyFromMnemonic(phrase);
      final String signedB64;
      try {
        signedB64 = XrpBackendTransfer.signCreateTransactionData(
          data: data,
          privateKey: pk,
          expectedOwnerClassicAddress: owner,
        );
      } catch (e) {
        rethrow;
      }
      final broad = await _transferApi.broadcastTransaction(
        chain: chain,
        coin: coin,
        data: signedB64,
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

    if (kind == ChainKind.ton) {
      final wid = _activeWalletId;
      if (wid == null) {
        throw StateError('未选择钱包');
      }
      final phrase = await _storage.readMnemonicForWallet(wid);
      if (phrase == null || phrase.trim().isEmpty) {
        throw StateError('无法读取助记词');
      }
      final testOnly = HdWalletService.tonTestOnlyHeuristic(cfg);
      final owner =
          testOnly ? (_tonAddressTest ?? '') : (_tonAddressMain ?? '');
      if (owner.isEmpty) {
        throw StateError('TON 地址未就绪');
      }
    final create = await _transferApi.createTransaction(
      chain: chain,
      coin: coin,
      ownerAddress: owner,
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
      final data = _asMap(create['data']);
      final pk = await TonBackendTransfer.privateKeyFromMnemonic(phrase);
      final broadcastPayload = await TonBackendTransfer.prepareBroadcastData(
        data: data,
        privateKey: pk,
        expectedOwnerFriendly: owner,
        testOnly: testOnly,
        fallbackAmountTon: amount,
      );
      final broad = await _transferApi.broadcastTransaction(
        chain: chain,
        coin: coin,
        data: broadcastPayload,
      );
      if (broad == null) {
        throw StateError('broadcastTransaction 无响应');
      }
      if (broad['code'] != 0) {
        final msg = broad['message']?.toString() ?? 'broadcastTransaction 失败';
        throw StateError(msg);
      }
      final h = _readTxHashFromBroadcast(broad['data']);
      return h ?? broadcastPayload;
    }

    if (kind == ChainKind.btc) {
      return _signBroadcastUtxoTransfer(
        cfg: cfg,
        chain: chain,
        coin: coin,
        toAddress: toAddress,
        amount: amount,
        gasPriceType: gasPriceType,
        testnet: HdWalletService.btcTestnetHeuristic(cfg),
        ownerMainnet: _btcMainnetAddress,
        ownerTestnet: _btcTestnetAddress,
        derivationPathMainnet: kBtcMainnetBip84Path,
        derivationPathTestnet: kBtcTestnetBip84Path,
        notReadyLabel: 'BTC',
        doge: false,
      );
    }

    if (kind == ChainKind.doge) {
      return _signBroadcastUtxoTransfer(
        cfg: cfg,
        chain: chain,
        coin: coin,
        toAddress: toAddress,
        amount: amount,
        gasPriceType: gasPriceType,
        testnet: HdWalletService.dogeTestnetHeuristic(cfg),
        ownerMainnet: _dogeMainnetAddress,
        ownerTestnet: _dogeTestnetAddress,
        derivationPathMainnet: kDogeDefaultDerivationPath,
        derivationPathTestnet: kDogeDefaultDerivationPath,
        notReadyLabel: 'DOGE',
        doge: true,
      );
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
      final signed = TronTransactionSigner.signApiData(data, pk);
      final broad = await _transferApi.broadcastTransaction(
        chain: chain,
        coin: coin,
        data: signed.signedJson,
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
      return h ?? (data['txId']?.toString() ?? signed.signatureHex);
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
}
