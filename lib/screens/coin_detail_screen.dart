import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web3dart/web3dart.dart';

import '../config/evm_environment.dart';
import '../models/coin_data.dart';
import '../models/evm_network.dart';
import '../providers/wallet_controller.dart';
import '../services/evm/blockscout_account_tx_service.dart';
import '../theme/app_colors.dart';
import 'flash_screen.dart';
import 'receive_screen.dart';
import 'transfer_screen.dart';

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

String _shortTxHash(String hash) {
  final h = hash.startsWith('0x') ? hash : '0x$hash';
  if (h.length <= 18) {
    return h;
  }
  return '${h.substring(0, 10)}…${h.substring(h.length - 8)}';
}

String _formatTxListTime(DateTime t) {
  final now = DateTime.now();
  final d = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  final hm =
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  if (d == today) {
    return '今天 $hm';
  }
  return '${t.month}/${t.day} $hm';
}

String _shortAddr(String raw) {
  final a = raw.trim();
  if (a.isEmpty) {
    return '';
  }
  final s = a.startsWith('0x') ? a : '0x$a';
  if (s.length <= 14) {
    return s;
  }
  return '${s.substring(0, 8)}…${s.substring(s.length - 4)}';
}

/// 确认数低于此值视为「待确认」（与常见 12 块近似确认习惯一致，可调）。
const int _kTxPendingConfirmationsThreshold = 12;

enum _TxChipFilter {
  all,
  receive,
  send,
  pending,
  gasOnly,
}

List<BlockscoutAccountTx> _visibleTransactions(
  List<BlockscoutAccountTx> txs,
  _TxChipFilter filter,
  String walletHex,
) {
  if (txs.isEmpty) {
    return txs;
  }
  return txs.where((tx) {
    final out = tx.isOutgoing(walletHex);
    switch (filter) {
      case _TxChipFilter.all:
        return true;
      case _TxChipFilter.receive:
        return !out;
      case _TxChipFilter.send:
        return out && tx.valueWei > BigInt.zero;
      case _TxChipFilter.pending:
        return (tx.confirmations ?? 999999) < _kTxPendingConfirmationsThreshold;
      case _TxChipFilter.gasOnly:
        return out && tx.valueWei == BigInt.zero;
    }
  }).toList();
}

String _formatTxEthAmount(BigInt wei) {
  try {
    final v = EtherAmount.inWei(wei).getValueInUnit(EtherUnit.ether);
    if (v == 0) {
      return '0';
    }
    if (v.abs() >= 1) {
      return v
          .toStringAsFixed(5)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
    return v
        .toStringAsFixed(6)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  } catch (_) {
    return '—';
  }
}

class CoinDetailScreen extends StatefulWidget {
  final CoinData coin;
  const CoinDetailScreen({super.key, required this.coin});

  @override
  State<CoinDetailScreen> createState() => _CoinDetailScreenState();
}

class _CoinDetailScreenState extends State<CoinDetailScreen> {
  final BlockscoutAccountTxService _txService = BlockscoutAccountTxService();
  List<BlockscoutAccountTx> _txs = const [];
  bool _txLoading = false;
  String? _txError;
  int _txRequestGen = 0;
  _TxChipFilter _txFilter = _TxChipFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTxs();
    });
  }

  Future<void> _loadTxs() async {
    final wc = context.read<WalletController>();
    final addr = wc.addressHex;
    final live = _liveCoin(wc, widget.coin);
    final net = EvmEnvironment.networkIdForChainId(live.chainId);
    final root = net != null ? EvmEnvironment.blockscoutApiRoot(net) : null;
    final gen = ++_txRequestGen;
    if (!mounted) {
      return;
    }
    if (addr == null || root == null) {
      setState(() {
        _txs = const [];
        _txLoading = false;
        _txError = null;
      });
      return;
    }
    setState(() {
      _txError = null;
      if (_txs.isEmpty) {
        _txLoading = true;
      }
    });
    try {
      final list = await _txService.fetchTxList(apiRoot: root, address: addr);
      if (!mounted || gen != _txRequestGen) {
        return;
      }
      setState(() {
        _txs = list;
        _txLoading = false;
      });
    } catch (e) {
      if (!mounted || gen != _txRequestGen) {
        return;
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

  Future<void> _openExplorerTx(EvmNetworkId net, String hash) async {
    final uri = Uri.parse(EvmEnvironment.explorerTxUrl(net, hash));
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _openExplorerAddress(EvmNetworkId net, String address) async {
    final uri = Uri.parse(EvmEnvironment.explorerAddressUrl(net, address));
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final wc = context.watch<WalletController>();
    final live = _liveCoin(wc, widget.coin);
    final evmNet = EvmEnvironment.networkIdForChainId(live.chainId);
    final subtitle = _walletAddressSubtitle(wc);
    final walletHex = wc.addressHex;
    final visibleTxs = walletHex == null
        ? const <BlockscoutAccountTx>[]
        : _visibleTransactions(_txs, _txFilter, walletHex);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: Text(live.symbol,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        actions: const [
          Icon(Icons.tune, color: AppColors.textPrimary, size: 22),
          SizedBox(width: 12),
          Icon(Icons.more_vert, color: AppColors.textPrimary, size: 22),
          SizedBox(width: 8),
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
                            const Row(
                              children: [
                                Text('交易',
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600)),
                                SizedBox(width: 16),
                                Text('资讯',
                                    style: TextStyle(
                                        fontSize: 18,
                                        color: AppColors.textSecondary)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                width: 34,
                                child: Divider(
                                    thickness: 3, color: AppColors.accent),
                              ),
                            ),
                            const SizedBox(height: 7),
                            Row(
                              children: [
                                Expanded(
                                  child: _TagChip(
                                    label: '全部',
                                    selected: _txFilter == _TxChipFilter.all,
                                    onTap: () => setState(
                                        () => _txFilter = _TxChipFilter.all),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _TagChip(
                                    label: '收款',
                                    selected:
                                        _txFilter == _TxChipFilter.receive,
                                    onTap: () => setState(() =>
                                        _txFilter = _TxChipFilter.receive),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _TagChip(
                                    label: '转账',
                                    selected: _txFilter == _TxChipFilter.send,
                                    onTap: () => setState(
                                        () => _txFilter = _TxChipFilter.send),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _TagChip(
                                    label: '待确认',
                                    selected:
                                        _txFilter == _TxChipFilter.pending,
                                    onTap: () => setState(() =>
                                        _txFilter = _TxChipFilter.pending),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _TagChip(
                                    label: '矿工费',
                                    selected:
                                        _txFilter == _TxChipFilter.gasOnly,
                                    onTap: () => setState(() =>
                                        _txFilter = _TxChipFilter.gasOnly),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                    if (_txLoading && _txs.isEmpty)
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
                    if (_txError != null)
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
                    if (!_txLoading &&
                        _txError == null &&
                        _txs.isEmpty &&
                        evmNet != null &&
                        wc.addressHex != null)
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
                              const Text('暂无记录',
                                  style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 18)),
                              const SizedBox(height: 18),
                              TextButton(
                                onPressed: () {
                                  final h = wc.addressHex;
                                  if (h != null) {
                                    _openExplorerAddress(evmNet, h);
                                  }
                                },
                                child: const Text(
                                  '在区块浏览器中查看',
                                  style: TextStyle(
                                      color: AppColors.accent, fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (!_txLoading &&
                        _txError == null &&
                        _txs.isEmpty &&
                        (evmNet == null || wc.addressHex == null))
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
                              const Text('暂无记录',
                                  style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 18)),
                            ],
                          ),
                        ),
                      ),
                    if (!_txLoading &&
                        _txError == null &&
                        _txs.isNotEmpty &&
                        visibleTxs.isEmpty)
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
                    if (visibleTxs.isNotEmpty)
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final tx = visibleTxs[index];
                            final addr = wc.addressHex;
                            if (addr == null || evmNet == null) {
                              return const SizedBox.shrink();
                            }
                            final outgoing = tx.isOutgoing(addr);
                            final counter =
                                outgoing ? tx.to.trim() : tx.from.trim();
                            final counterLabel =
                                counter.isEmpty ? '合约创建' : _shortAddr(counter);
                            final amt = _formatTxEthAmount(tx.valueWei);
                            final sign = outgoing ? '-' : '+';
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _openExplorerTx(evmNet, tx.hash),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 4),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        outgoing
                                            ? Icons.north_east
                                            : Icons.south_west,
                                        size: 22,
                                        color: outgoing
                                            ? AppColors.textSecondary
                                            : const Color(0xFF10E8CF),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              outgoing ? '转出' : '收款',
                                              style: const TextStyle(
                                                color: AppColors.textPrimary,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              counterLabel,
                                              style: const TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 13,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _shortTxHash(tx.hash),
                                              style: const TextStyle(
                                                color: AppColors.textMuted,
                                                fontSize: 12,
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
                                            '$sign$amt ${live.symbol}',
                                            style: TextStyle(
                                              color: tx.isSuccess
                                                  ? (outgoing
                                                      ? AppColors.textPrimary
                                                      : const Color(0xFF10E8CF))
                                                  : AppColors.error,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _formatTxListTime(tx.timestamp),
                                            style: const TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 12,
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
                          childCount: visibleTxs.length,
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
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const ReceiveScreen()),
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
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const TransferScreen()),
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
    final symbol = coin.symbol.toUpperCase();
    if (symbol == 'BNB') {
      return Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(
          color: Color(0xFFF0B90B),
          shape: BoxShape.circle,
        ),
        child: const Stack(
          alignment: Alignment.center,
          children: [
            Positioned(top: 12, child: _Diamond(size: 5)),
            Positioned(bottom: 14, child: _Diamond(size: 5)),
            Positioned(left: 12, child: _Diamond(size: 5)),
            Positioned(right: 12, child: _Diamond(size: 5)),
            Positioned(top: 23, child: _Diamond(size: 8)),
          ],
        ),
      );
    }

    if (symbol == 'ETH') {
      return Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(
          color: Color(0xFF6B7280),
          shape: BoxShape.circle,
        ),
        child: const Center(child: _Diamond(size: 12)),
      );
    }

    if (symbol == 'BTC') {
      return const CircleAvatar(
        radius: 28,
        backgroundColor: Color(0xFFF7931A),
        child: Text('₿',
            style: TextStyle(
                fontSize: 24,
                color: Colors.white,
                fontWeight: FontWeight.w700)),
      );
    }

    return CircleAvatar(
      radius: 28,
      backgroundColor: const Color(0xFF4B5563),
      child: Text(
        symbol.substring(0, 1),
        style: const TextStyle(
            fontSize: 22, color: Colors.white, fontWeight: FontWeight.w700),
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

class _Diamond extends StatelessWidget {
  final double size;
  const _Diamond({required this.size});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.785398, // 45°
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(1.2)),
        ),
      ),
    );
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
          width: double.infinity,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : Colors.transparent,
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.borderSoft,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
