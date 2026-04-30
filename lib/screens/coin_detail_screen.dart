import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/chain_transaction_vo.dart';
import '../models/coin_data.dart';
import '../providers/wallet_controller.dart';
import '../services/wallet/chain_rules.dart';
import '../services/wallet/wallet_transaction_service.dart';
import '../theme/app_colors.dart';
import '../widgets/coin_icon.dart';
import 'flash_screen.dart';
import 'receive_screen.dart';
import 'transfer_screen.dart';
import 'wallet_transaction_detail_screen.dart';

CoinData _liveCoin(WalletController wc, CoinData initial) {
  for (final c in wc.evmCoins) {
    if (c.id == initial.id) {
      return c;
    }
  }
  return initial;
}

String _walletAddressSubtitle(WalletController wc) {
  final name = wc.activeWallet?.name;
  final hex = wc.addressHex;
  if (hex == null || hex.length < 10) {
    return name ?? '未连接钱包';
  }
  final short = '${hex.substring(0, 6)}…${hex.substring(hex.length - 4)}';
  if (name != null && name.isNotEmpty) {
    return '$name  $short';
  }
  return short;
}

/// 交易历史列表右侧日期（与设计稿 `yyyy-MM-dd` 一致）。
String _formatTxHistoryDate(DateTime t) {
  final x = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${x.year}-${two(x.month)}-${two(x.day)}';
}

String _midTruncAddrForTxList(String raw, ChainKind kind) {
  final a = _txAddrUi(raw, kind);
  if (a.length <= 22) {
    return a;
  }
  return '${a.substring(0, 10)}…${a.substring(a.length - 10)}';
}

Uri? _joinExplorerUrl(String? prefix, String pathTail) {
  final p = prefix?.trim();
  if (p == null || p.isEmpty) {
    return null;
  }
  final t = pathTail.trim();
  if (t.isEmpty) {
    return null;
  }
  final b = p.endsWith('/') ? p : '$p/';
  return Uri.tryParse('$b$t');
}

String _coinNetworkSubtitle(CoinData live) {
  final n = (live.network ?? '').trim();
  final c = live.chainId;
  if (n.isNotEmpty && c != null) {
    return '$n · Chain $c';
  }
  if (n.isNotEmpty) {
    return n;
  }
  if (c != null) {
    return 'Chain $c';
  }
  final kind = ChainRules.kindFromChainQuery(live.walletApiChainQuery);
  return kind == ChainKind.tron ? 'TRON' : 'EVM';
}

String _txHistorySubtitleFromTo(bool outgoing, String counter, ChainKind kind) {
  if (counter.isEmpty) {
    return '合约创建';
  }
  final body = _midTruncAddrForTxList(counter, kind);
  return outgoing ? 'To: $body' : 'From: $body';
}

/// 交易历史列表左侧圆标（收款向下绿箭头 / 转账向上灰箭头）。
Widget _txHistoryCircleIcon(bool outgoing) {
  return Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: outgoing ? AppColors.surfaceElevated : const Color(0xFF0D2F28),
      shape: BoxShape.circle,
    ),
    alignment: Alignment.center,
    child: Icon(
      outgoing ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
      size: 22,
      color: outgoing ? AppColors.textSecondary : const Color(0xFF10E8CF),
    ),
  );
}

enum _TxChipFilter {
  all,
  receive,
  send,
  pending,
  gasOnly,
}

String _txAddrKey(String raw, ChainKind kind) {
  return ChainRules.normalizeAddressForStorage(kind, raw);
}

String _txAddrUi(String raw, ChainKind kind) {
  return ChainRules.formatAddressForUi(kind, raw);
}

/// 与后端 `fundDirection`（in/out）或 from 地址推断一致。
bool _apiTxIsOutgoing(
    ChainTransactionVo tx, String walletAddress, ChainKind kind) {
  final fd = tx.fundDirection?.toLowerCase().trim();
  if (fd == 'out' || fd == 'send' || fd == 'outgoing') {
    return true;
  }
  if (fd == 'in' || fd == 'receive' || fd == 'incoming') {
    return false;
  }
  final w = _txAddrKey(walletAddress, kind);
  final from = tx.fromAddress?.trim() ?? '';
  if (from.isEmpty) {
    return false;
  }
  return _txAddrKey(from, kind) == w;
}

List<ChainTransactionVo> _visibleApiTransactions(
  List<ChainTransactionVo> txs,
  _TxChipFilter filter,
  String walletAddress,
  ChainKind kind,
) {
  if (txs.isEmpty) {
    return txs;
  }
  return txs.where((tx) {
    final out = _apiTxIsOutgoing(tx, walletAddress, kind);
    final q = tx.quantity ?? 0;
    switch (filter) {
      case _TxChipFilter.all:
        return true;
      case _TxChipFilter.receive:
        return !out;
      case _TxChipFilter.send:
        return out && q > 0;
      case _TxChipFilter.pending:
        final bn = tx.blockNumber?.trim() ?? '';
        return bn.isEmpty;
      case _TxChipFilter.gasOnly:
        return out && q == 0;
    }
  }).toList();
}

String _formatApiQuantity(double? q) {
  if (q == null) {
    return '—';
  }
  if (q == 0) {
    return '0';
  }
  final v = q.abs();
  if (v >= 1) {
    return q
        .toStringAsFixed(5)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
  return q
      .toStringAsFixed(6)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// 后端 `status`：`0` / `1` 视为成功，其余视为失败态展示。
bool _apiTxLooksSuccessful(ChainTransactionVo tx) {
  final s = tx.status;
  if (s == null || s == 0 || s == 1) {
    return true;
  }
  return false;
}

class CoinDetailScreen extends StatefulWidget {
  final CoinData coin;
  const CoinDetailScreen({super.key, required this.coin});

  @override
  State<CoinDetailScreen> createState() => _CoinDetailScreenState();
}

class _CoinDetailScreenState extends State<CoinDetailScreen> {
  final WalletTransactionService _txDetailService = WalletTransactionService();

  /// 非 `null` 表示已成功走过后端列表接口（含空列表）。
  List<ChainTransactionVo>? _txsFromApi;
  bool _txLoading = false;
  String? _txError;
  int _txRequestGen = 0;
  _TxChipFilter _txFilter = _TxChipFilter.all;
  bool _txShowTransactionsTab = true;

  bool _txCompositeEmpty() => _txsFromApi != null ? _txsFromApi!.isEmpty : true;

  bool _txHasRows() => _txsFromApi != null ? _txsFromApi!.isNotEmpty : false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTxs();
    });
  }

  Future<void> _loadTxs() async {
    final wc = context.read<WalletController>();
    final live = _liveCoin(wc, widget.coin);
    final gen = ++_txRequestGen;
    if (!mounted) {
      return;
    }
    setState(() {
      _txError = null;
      if (_txCompositeEmpty()) {
        _txLoading = true;
      }
    });
    try {
      final chain = wc.chainParamForCoin(live);
      if (chain.isEmpty) {
        throw StateError('缺少 chain 参数（请确认 /api/app/chains 已返回该资产对应链）');
      }
      final kind = ChainRules.kindFromChainQuery(chain);
      final address = kind == ChainKind.tron
          ? (wc.tronAddress ?? '')
          : ChainRules.formatAddressForUi(ChainKind.evm, wc.addressHex ?? '');
      if (address.isEmpty) {
        throw StateError('缺少地址，无法拉取交易记录');
      }
      final cache = wc.localCache;
      final scope = cache?.transactionScopeKey(address, chain, live.symbol);
      if (cache != null && scope != null) {
        try {
          final cached = await cache.getTransactionHistory(scope);
          if (!mounted || gen != _txRequestGen) {
            return;
          }
          // 仅有「有内容的缓存」才先画屏；空列表不抢占 UI，继续走接口，避免先显示全空
          if (cached != null && cached.isNotEmpty) {
            setState(() {
              _txsFromApi = cached;
              _txLoading = false;
              _txError = null;
            });
          }
        } catch (_) {
          // 缓存读失败不能阻塞拉取接口
        }
      }

      final apiList = await _txDetailService.fetchTransactionHistory(
        address: address,
        chain: chain,
        coin: live.symbol,
      );
      if (!mounted || gen != _txRequestGen) {
        return;
      }
      if (apiList != null) {
        if (cache != null && scope != null) {
          unawaited(cache.replaceTransactionHistory(scope, apiList));
        }
        setState(() {
          _txsFromApi = apiList;
          _txLoading = false;
          _txError = null;
        });
      } else {
        List<ChainTransactionVo>? fromDisk;
        if (cache != null && scope != null) {
          try {
            fromDisk = await cache.getTransactionHistory(scope);
          } catch (_) {
            fromDisk = null;
          }
        }
        setState(() {
          if (fromDisk != null) {
            _txsFromApi = fromDisk;
            _txError = '网络异常，已显示本地缓存。';
          } else {
            _txsFromApi = const [];
            _txError = '交易记录暂不可用，请检查网络。';
          }
          _txLoading = false;
        });
      }
    } catch (e) {
      if (!mounted || gen != _txRequestGen) {
        return;
      }
      final cache = wc.localCache;
      if (cache != null) {
        try {
          final chain2 = wc.chainParamForCoin(live);
          final kind2 = ChainRules.kindFromChainQuery(chain2);
          final ad = kind2 == ChainKind.tron
              ? (wc.tronAddress ?? '')
              : ChainRules.formatAddressForUi(
                  ChainKind.evm, wc.addressHex ?? '');
          final sc = cache.transactionScopeKey(ad, chain2, live.symbol);
          final fromDisk = await cache.getTransactionHistory(sc);
          if (fromDisk != null) {
            setState(() {
              _txsFromApi = fromDisk;
              _txError = '网络异常，已显示本地缓存。';
              _txLoading = false;
            });
            return;
          }
        } catch (_) {}
      }
      setState(() {
        _txError = e.toString();
        _txLoading = false;
      });
    }
  }

  /// 顺序执行，避免与 [WalletController.notifyListeners] 触发的重建交错导致异常或假死感。
  Future<void> _onPullRefresh() async {
    final wc = context.read<WalletController>();
    await wc.refreshBalances();
    if (!mounted) {
      return;
    }
    await _loadTxs();
  }

  Future<void> _openExplorerTxForCoin(CoinData live, String rawHash) async {
    final wc = context.read<WalletController>();
    final chain = wc.chainParamForCoin(live);
    final kind = ChainRules.kindFromChainQuery(chain);
    final h = kind == ChainKind.tron
        ? rawHash.trim()
        : (rawHash.trim().startsWith('0x')
            ? rawHash.trim()
            : '0x${rawHash.trim()}');
    final link = _joinExplorerUrl(live.txUrlPrefix, h);
    if (link == null) {
      return;
    }
    try {
      await launchUrl(link, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _openExplorerAddressForCoin(
      CoinData live, String rawAddr) async {
    final wc = context.read<WalletController>();
    final chain = wc.chainParamForCoin(live);
    final kind = ChainRules.kindFromChainQuery(chain);
    final a = ChainRules.formatAddressForUi(kind, rawAddr);
    final link = _joinExplorerUrl(live.addressUrlPrefix, a);
    if (link == null) {
      return;
    }
    try {
      await launchUrl(link, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// 列表底部「在区块浏览器中查看」：优先用接口返回的 [ChainTransactionVo.addressLinkPrefix]。
  Future<void> _openHistoryExplorerAddress(
    WalletController wc,
    CoinData live,
    bool useApiList,
    List<ChainTransactionVo> apiVisible,
  ) async {
    final chain = wc.chainParamForCoin(live);
    final kind = ChainRules.kindFromChainQuery(chain);
    final walletAddr = kind == ChainKind.tron ? wc.tronAddress : wc.addressHex;
    if (walletAddr == null) {
      return;
    }
    final normalized = ChainRules.formatAddressForUi(kind, walletAddr);
    if (useApiList && apiVisible.isNotEmpty) {
      final p = apiVisible.first.addressLinkPrefix?.trim();
      if (p != null && p.isNotEmpty) {
        final uri = Uri.tryParse(
          p.endsWith('/') ? '$p$normalized' : '$p/$normalized',
        );
        if (uri != null) {
          try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (_) {}
          return;
        }
      }
    }
    await _openExplorerAddressForCoin(live, normalized);
  }

  /// [apiListRow] 来自 `transactionHistory` 时，若 [ChainTransactionVo.walletHistoryRowIncludesDetail] 为真则不再请求详情接口。
  Future<void> _onTapTransaction(
    CoinData live,
    String rawTxHash, {
    ChainTransactionVo? apiListRow,
  }) async {
    final wc = context.read<WalletController>();
    if (apiListRow != null && apiListRow.walletHistoryRowIncludesDetail) {
      _openWalletTransactionDetail(wc, live, rawTxHash, apiListRow);
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      ),
    );
    final chain = wc.chainParamForCoin(live);
    final kind = ChainRules.kindFromChainQuery(chain);
    final h = kind == ChainKind.tron
        ? rawTxHash
        : (rawTxHash.startsWith('0x') ? rawTxHash : '0x$rawTxHash');
    final detail = await _txDetailService.fetchTransactionDetail(
      txHash: h,
      chain: chain,
      crypto: live.symbol,
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
    if (detail == null) {
      await _openExplorerTxForCoin(live, rawTxHash);
      return;
    }
    _openWalletTransactionDetail(wc, live, rawTxHash, detail);
  }

  void _openWalletTransactionDetail(
    WalletController wc,
    CoinData live,
    String rawTxHash,
    ChainTransactionVo detail,
  ) {
    final chain = wc.chainParamForCoin(live);
    final kind = ChainRules.kindFromChainQuery(chain);
    final walletAddr = kind == ChainKind.tron ? wc.tronAddress : wc.addressHex;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => WalletTransactionDetailScreen(
          detail: detail,
          coin: live,
          rawTxHash: rawTxHash,
          walletHex: walletAddr,
        ),
      ),
    );
  }

  void _showMoreSheet({
    required CoinData live,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => _CoinDetailMoreSheet(live: live),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wc = context.watch<WalletController>();
    final live = _liveCoin(wc, widget.coin);
    final hasChain = wc.chainParamForCoin(live).trim().isNotEmpty;
    final subtitle = _walletAddressSubtitle(wc);
    final chain = wc.chainParamForCoin(live);
    final kind = ChainRules.kindFromChainQuery(chain);
    final walletAddr = kind == ChainKind.tron ? wc.tronAddress : wc.addressHex;
    final useApiList = _txsFromApi != null;
    final visibleTxsApi = (walletAddr == null || !useApiList)
        ? const <ChainTransactionVo>[]
        : _visibleApiTransactions(_txsFromApi!, _txFilter, walletAddr, kind);
    final filterEmpty = useApiList ? visibleTxsApi.isEmpty : true;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: Text(live.symbol,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            onPressed: () {},
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            icon:
                const Icon(Icons.tune, color: AppColors.textPrimary, size: 22),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: !hasChain ? null : () => _showMoreSheet(live: live),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            icon: const Icon(Icons.more_vert,
                color: AppColors.textPrimary, size: 22),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: _onPullRefresh,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.zero,
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const CircleAvatar(
                                  radius: 11,
                                  backgroundColor: Color(0xFF2C2F37),
                                  child: Icon(Icons.description_outlined,
                                      size: 14, color: AppColors.textSecondary),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    subtitle,
                                    style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.copy,
                                    size: 13, color: AppColors.textMuted),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                _tokenAvatar(live),
                                const SizedBox(width: 14),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _displayBalance(live.balance),
                                      style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize:
                                            _balanceFontSize(live.balance),
                                        fontWeight: FontWeight.w700,
                                        height: 1,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    live.price == 0
                                        ? Text(
                                            '\$${live.balanceUSD.toStringAsFixed(live.balanceUSD == 0 ? 0 : 4)} | 未接入行情',
                                            style: const TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 14),
                                          )
                                        : RichText(
                                            text: TextSpan(
                                              style: const TextStyle(
                                                  color:
                                                      AppColors.textSecondary,
                                                  fontSize: 14),
                                              children: [
                                                TextSpan(
                                                  text:
                                                      '\$${live.balanceUSD.toStringAsFixed(live.balanceUSD == 0 ? 0 : 4)} | \$${live.price.toStringAsFixed(2)}  ',
                                                ),
                                                TextSpan(
                                                  text:
                                                      '${live.priceChange24h >= 0 ? '+' : ''}${live.priceChange24h.toStringAsFixed(2)}%',
                                                  style: TextStyle(
                                                    color:
                                                        live.priceChange24h < 0
                                                            ? AppColors.error
                                                            : const Color(
                                                                0xFF10E8CF),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 13),
                            Row(
                              children: [
                                Expanded(
                                  child: _quick(context, Icons.north_east, '闪兑',
                                      () {
                                    Navigator.of(context).push(
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const FlashScreen()));
                                  }),
                                ),
                                Expanded(
                                  child: _quick(context,
                                      Icons.local_gas_station, '买Gas', () {}),
                                ),
                                Expanded(
                                  child: _quick(context, Icons.person_outline,
                                      '授权', () {}),
                                ),
                                Expanded(
                                  child: _quick(context,
                                      Icons.inventory_2_outlined, '浏览器', () {}),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _quick(context, Icons.travel_explore,
                                      'CoinGecko', () {}),
                                ),
                                Expanded(
                                  child: _quick(context, Icons.hexagon_outlined,
                                      'SoSoValue', () {}),
                                ),
                                const Expanded(child: SizedBox()),
                                const Expanded(child: SizedBox()),
                              ],
                            ),
                            const SizedBox(height: 15),
                          ],
                        ),
                      ),
                    ),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _CoinDetailStickyTxHeaderDelegate(
                        extent: _txShowTransactionsTab ? 112 : 52,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => setState(
                                        () => _txShowTransactionsTab = true),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '交易',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            color: _txShowTransactionsTab
                                                ? AppColors.textPrimary
                                                : AppColors.textSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 200),
                                          height: 3,
                                          width:
                                              _txShowTransactionsTab ? 36 : 0,
                                          decoration: BoxDecoration(
                                            color: _txShowTransactionsTab
                                                ? AppColors.accent
                                                : Colors.transparent,
                                            borderRadius:
                                                BorderRadius.circular(2),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 24),
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => setState(
                                        () => _txShowTransactionsTab = false),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '资讯',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            color: !_txShowTransactionsTab
                                                ? AppColors.textPrimary
                                                : AppColors.textSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 200),
                                          height: 3,
                                          width:
                                              !_txShowTransactionsTab ? 36 : 0,
                                          decoration: BoxDecoration(
                                            color: !_txShowTransactionsTab
                                                ? AppColors.accent
                                                : Colors.transparent,
                                            borderRadius:
                                                BorderRadius.circular(2),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (_txShowTransactionsTab) ...[
                                const SizedBox(height: 12),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      _TagChip(
                                        label: '全部',
                                        selected:
                                            _txFilter == _TxChipFilter.all,
                                        onTap: () => setState(() =>
                                            _txFilter = _TxChipFilter.all),
                                      ),
                                      const SizedBox(width: 8),
                                      _TagChip(
                                        label: '收款',
                                        selected:
                                            _txFilter == _TxChipFilter.receive,
                                        onTap: () => setState(() =>
                                            _txFilter = _TxChipFilter.receive),
                                      ),
                                      const SizedBox(width: 8),
                                      _TagChip(
                                        label: '转账',
                                        selected:
                                            _txFilter == _TxChipFilter.send,
                                        onTap: () => setState(() =>
                                            _txFilter = _TxChipFilter.send),
                                      ),
                                      const SizedBox(width: 8),
                                      _TagChip(
                                        label: '待确认',
                                        selected:
                                            _txFilter == _TxChipFilter.pending,
                                        onTap: () => setState(() =>
                                            _txFilter = _TxChipFilter.pending),
                                      ),
                                      const SizedBox(width: 8),
                                      _TagChip(
                                        label: '矿工费',
                                        selected:
                                            _txFilter == _TxChipFilter.gasOnly,
                                        onTap: () => setState(() =>
                                            _txFilter = _TxChipFilter.gasOnly),
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 40,
                                          minHeight: 40,
                                        ),
                                        icon: const Icon(
                                          Icons.tune,
                                          color: AppColors.textSecondary,
                                          size: 22,
                                        ),
                                        onPressed: () {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                                content: Text('更多筛选开发中')),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (!_txShowTransactionsTab)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Text(
                            '资讯内容即将上线',
                            style: TextStyle(
                              color: AppColors.textSecondary
                                  .withValues(alpha: 0.95),
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    if (_txShowTransactionsTab &&
                        _txLoading &&
                        _txCompositeEmpty())
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 36),
                          child: Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_txShowTransactionsTab && _txError != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 24),
                          child: Text(
                            '交易记录加载失败：$_txError',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    if (_txShowTransactionsTab &&
                        !_txLoading &&
                        _txError == null &&
                        _txCompositeEmpty() &&
                        (wc.addressHex != null || wc.tronAddress != null))
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.description_outlined,
                                  size: 86,
                                  color: AppColors.textMuted
                                      .withValues(alpha: 0.9)),
                              const SizedBox(height: 8),
                              Text(
                                !hasChain
                                    ? '缺少链信息，无法展示交易记录'
                                    : (live.addressUrlPrefix == null ||
                                            live.addressUrlPrefix!
                                                .trim()
                                                .isEmpty)
                                        ? '暂无记录'
                                        : '暂无记录',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 18),
                              ),
                              if (hasChain &&
                                  live.addressUrlPrefix != null &&
                                  live.addressUrlPrefix!.trim().isNotEmpty) ...[
                                const SizedBox(height: 18),
                                TextButton(
                                  onPressed: () {
                                    final h = wc.addressHex;
                                    if (h != null) {
                                      _openExplorerAddressForCoin(live, h);
                                    }
                                  },
                                  child: const Text(
                                    '在区块浏览器中查看',
                                    style: TextStyle(
                                        color: AppColors.accent, fontSize: 14),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    if (_txShowTransactionsTab &&
                        !_txLoading &&
                        _txError == null &&
                        _txHasRows() &&
                        filterEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.filter_list_off,
                                  size: 56,
                                  color: AppColors.textMuted
                                      .withValues(alpha: 0.85)),
                              const SizedBox(height: 12),
                              const Text(
                                '该分类下暂无交易',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_txShowTransactionsTab && visibleTxsApi.isNotEmpty)
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final tx = visibleTxsApi[index];
                            final addr = walletAddr;
                            if (addr == null) {
                              return const SizedBox.shrink();
                            }
                            final outgoing = _apiTxIsOutgoing(tx, addr, kind);
                            final counter = outgoing
                                ? (tx.toAddress ?? '').trim()
                                : (tx.fromAddress ?? '').trim();
                            final subtitle = _txHistorySubtitleFromTo(
                                outgoing, counter, kind);
                            final amt = _formatApiQuantity(tx.quantity);
                            final sign = outgoing ? '-' : '+';
                            final hash = tx.txHash ?? '';
                            final t = tx.transactionTime?.toLocal();
                            final ok = _apiTxLooksSuccessful(tx);
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _onTapTransaction(
                                  live,
                                  hash,
                                  apiListRow: tx,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14, horizontal: 2),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _txHistoryCircleIcon(outgoing),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              outgoing ? '转账' : '收款',
                                              style: const TextStyle(
                                                color: AppColors.textPrimary,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              subtitle,
                                              style: const TextStyle(
                                                color: AppColors.textMuted,
                                                fontSize: 13,
                                                height: 1.25,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '$sign$amt ${tx.crypto ?? live.symbol}',
                                            style: TextStyle(
                                              color: ok
                                                  ? AppColors.textPrimary
                                                  : AppColors.error,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            t != null
                                                ? _formatTxHistoryDate(t)
                                                : '—',
                                            style: const TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                          childCount: visibleTxsApi.length,
                        ),
                      ),
                    if (_txShowTransactionsTab && visibleTxsApi.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 20),
                          child: Center(
                            child: TextButton(
                              onPressed: () => _openHistoryExplorerAddress(
                                wc,
                                live,
                                useApiList,
                                visibleTxsApi,
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '在区块浏览器中查看',
                                    style: TextStyle(
                                      color: AppColors.accent,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    color: AppColors.accent,
                                    size: 22,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: OutlinedButton(
                      onPressed: () {
                        final wc = context.read<WalletController>();
                        final chain = wc.chainParamForCoin(widget.coin);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) =>
                                  ReceiveScreen(initialChain: chain)),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: Color(0xFF3A3F54), width: 1.2),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text(
                        '收款',
                        style: TextStyle(
                          fontSize: 18,
                          color: Color(0xFFE7EBFF),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [AppColors.accentStart, AppColors.accentEnd],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            final wc = context.read<WalletController>();
                            final chain = wc.chainParamForCoin(widget.coin);
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      TransferScreen(initialChain: chain)),
                            );
                          },
                          child: const Center(
                            child: Text(
                              '转账',
                              style: TextStyle(
                                fontSize: 18,
                                color: AppColors.accentText,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _quick(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.textPrimary, size: 22),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _tokenAvatar(CoinData coin) {
    return ClipOval(
      child: SizedBox(
        width: 56,
        height: 56,
        child: CoinIcon(symbol: coin.symbol, size: 56),
      ),
    );
  }

  String _displayBalance(double value) {
    if (value == 0) {
      return '0';
    }
    if (value >= 1) {
      return value
          .toStringAsFixed(4)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
    return value
        .toStringAsFixed(6)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  double _balanceFontSize(double value) {
    final text = _displayBalance(value);
    if (text.length <= 1) return 52;
    if (text.length <= 4) return 50;
    if (text.length <= 6) return 44;
    return 40;
  }
}

class _CoinDetailMoreSheet extends StatefulWidget {
  final CoinData live;
  const _CoinDetailMoreSheet({required this.live});

  @override
  State<_CoinDetailMoreSheet> createState() => _CoinDetailMoreSheetState();
}

class _CoinDetailMoreSheetState extends State<_CoinDetailMoreSheet> {
  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    const sheetBg = Color(0xFF2C2F37);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            decoration: const BoxDecoration(
              color: sheetBg,
              borderRadius: BorderRadius.all(Radius.circular(18)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 16,
                        backgroundColor: Color(0xFF1F2229),
                        child: Icon(Icons.account_balance_wallet_outlined,
                            size: 18, color: AppColors.textPrimary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.live.symbol,
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _coinNetworkSubtitle(widget.live),
                              style: const TextStyle(
                                  color: AppColors.textSecondary, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close,
                            color: AppColors.textSecondary, size: 20),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: const BoxDecoration(
                    color: Color(0xFF3A3E47),
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                  child: Column(
                    children: [
                      _SheetKVRow(
                        icon: Icons.public,
                        label: '网络',
                        value: (widget.live.network?.trim().isNotEmpty == true)
                            ? widget.live.network!.trim()
                            : '—',
                      ),
                      const Divider(height: 1, color: Color(0x332A2D35)),
                      const _SheetKVRow(
                        icon: Icons.vpn_key,
                        label: 'Path',
                        value: "m/44'/60'/0'/0/0",
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: const BoxDecoration(
                    color: Color(0xFF3A3E47),
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                  child: Column(
                    children: [
                      _SheetActionRow(
                        icon: Icons.language,
                        title: '在区块浏览器中查看',
                        onTap: () async {
                          final nav = Navigator.of(context);
                          final wc = context.read<WalletController>();
                          final h = wc.addressHex;
                          nav.pop();
                          if (h == null) {
                            return;
                          }
                          final uri = _joinExplorerUrl(
                            widget.live.addressUrlPrefix,
                            h.startsWith('0x') ? h : '0x$h',
                          );
                          if (uri == null) {
                            return;
                          }
                          try {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          } catch (_) {}
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // 用同色填满底部安全区，避免露出下面页面的按钮/空白。
                if (bottomInset > 0) SizedBox(height: bottomInset),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetKVRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _SheetKVRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 14)),
          ),
          Text(value,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _SheetActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const _SheetActionRow(
      {required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppColors.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ),
                const Icon(Icons.chevron_right,
                    color: AppColors.textMuted, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 币种详情：「交易 / 资讯」+ 筛选条吸顶。
class _CoinDetailStickyTxHeaderDelegate extends SliverPersistentHeaderDelegate {
  _CoinDetailStickyTxHeaderDelegate({
    required this.extent,
    required this.child,
  });

  final double extent;
  final Widget child;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      color: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: overlapsContent ? 2 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      child: SizedBox(
        height: extent,
        width: double.infinity,
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _CoinDetailStickyTxHeaderDelegate oldDelegate) {
    return extent != oldDelegate.extent || child != oldDelegate.child;
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TagChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : AppColors.surface,
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.borderSoft,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
