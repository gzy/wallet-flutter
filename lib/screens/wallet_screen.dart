import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/coin_data.dart';
import '../models/stored_wallet.dart';
import '../providers/wallet_controller.dart';
import '../theme/app_colors.dart';
import 'add_wallet_screen.dart';
import 'wallet_detail_screen.dart';
import 'flash_screen.dart';
import 'receive_screen.dart';
import 'transfer_screen.dart';
import 'wallet/widgets/wallet_actions_row.dart';
import 'wallet/widgets/wallet_balance_section.dart';
import 'wallet/widgets/wallet_coin_list.dart';
import 'wallet/widgets/wallet_header.dart';
import 'wallet/widgets/wallet_search_bar.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  bool _isBalanceVisible = true;
  final TextEditingController _searchController = TextEditingController();

  void _onSearchChanged() => setState(() {});

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openWalletManager() async {
    final wc = context.read<WalletController>();
    final list = wc.wallets;
    final nav = Navigator.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      barrierColor: Colors.black.withOpacity(0.6),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _WalletManagerSheet(
        wallets: list,
        selectedId: wc.activeWalletId ?? '',
        onSelect: (id) async {
          await context.read<WalletController>().switchWallet(id);
        },
        onAddWallet: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AddWalletScreen()),
          );
        },
        onOpenWalletDetails: (w) {
          Navigator.of(sheetContext).pop();
          nav.push<void>(
            MaterialPageRoute<void>(builder: (_) => WalletDetailScreen(wallet: w)),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletController>();
    final coins = wallet.hasWallet ? wallet.evmCoins : <CoinData>[];
    final headerName = wallet.activeWallet?.name ??
        (wallet.hasWallet && wallet.addressHex != null
            ? '${wallet.addressHex!.substring(0, 6)}…${wallet.addressHex!.substring(wallet.addressHex!.length - 4)}'
            : '未创建钱包');
    final q = _searchController.text.trim().toLowerCase();
    final coinsOnNetwork = coins.where((c) {
      final sel = wallet.sendChain;
      if (sel == null) {
        return true;
      }
      return wallet.chainParamForCoin(c) == sel;
    }).toList();
    final filteredCoins = q.isEmpty
        ? coinsOnNetwork
        : coinsOnNetwork
            .where((c) =>
                c.symbol.toLowerCase().contains(q) ||
                c.name.toLowerCase().contains(q) ||
                (c.network?.toLowerCase().contains(q) == true))
            .toList();

    final totalBalance = coinsOnNetwork.fold<double>(
        0, (sum, coin) => sum + coin.balanceUSD);

    return SafeArea(
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            WalletHeader(
              walletName: headerName,
              onOpenWalletManager: _openWalletManager,
              onOpenSettings: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('设置功能开发中')),
                );
              },
              onOpenNotifications: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('通知功能开发中')),
                );
              },
            ),
            Expanded(
              child: wallet.hasWallet && wallet.loading && coins.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        RefreshIndicator(
                          color: AppColors.accent,
                          onRefresh: () => context
                              .read<WalletController>()
                              .refreshWalletHome(),
                          child: CustomScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: [
                              SliverToBoxAdapter(
                                child: WalletBalanceSection(
                                  isBalanceVisible: _isBalanceVisible,
                                  totalBalance: totalBalance,
                                  totalBtcEquivalent: null,
                                  onToggleVisibility: () {
                                    setState(() {
                                      _isBalanceVisible = !_isBalanceVisible;
                                    });
                                  },
                                ),
                              ),
                              SliverToBoxAdapter(
                                child: WalletActionsRow(
                                  onTransfer: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                          builder: (_) => const TransferScreen()),
                                    );
                                  },
                                  onReceive: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                          builder: (_) => const ReceiveScreen()),
                                    );
                                  },
                                  onBuy: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('买币功能开发中')),
                                    );
                                  },
                                  onGas: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('加油站功能开发中')),
                                    );
                                  },
                                  onMore: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                          builder: (_) => const FlashScreen()),
                                    );
                                  },
                                ),
                              ),
                              SliverToBoxAdapter(
                                child: WalletSearchBar(controller: _searchController),
                              ),
                              const SliverToBoxAdapter(child: SizedBox(height: 6)),
                              WalletCoinList(coins: filteredCoins),
                            ],
                          ),
                        ),
                        if (wallet.hasWallet && wallet.loading && coins.isNotEmpty)
                          const Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: SizedBox(
                              height: 3,
                              child: LinearProgressIndicator(
                                backgroundColor: AppColors.surface,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletManagerSheet extends StatefulWidget {
  final List<StoredWallet> wallets;
  final String selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAddWallet;
  final ValueChanged<StoredWallet> onOpenWalletDetails;

  const _WalletManagerSheet({
    required this.wallets,
    required this.selectedId,
    required this.onSelect,
    required this.onAddWallet,
    required this.onOpenWalletDetails,
  });

  @override
  State<_WalletManagerSheet> createState() => _WalletManagerSheetState();
}

class _WalletManagerSheetState extends State<_WalletManagerSheet> {
  final TextEditingController _controller = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() => _q = _controller.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _q.isEmpty
        ? widget.wallets
        : widget.wallets.where((w) => w.name.toLowerCase().contains(_q)).toList();

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () async {
                      final wc = context.read<WalletController>();
                      final name = wc.activeWallet?.name ?? '';
                      final ctrl = TextEditingController(text: name);
                      final newName = await showDialog<String>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: AppColors.surface,
                          title: const Text('重命名钱包', style: TextStyle(color: AppColors.textPrimary)),
                          content: TextField(
                            controller: ctrl,
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: const InputDecoration(
                              hintText: '名称',
                              hintStyle: TextStyle(color: AppColors.textMuted),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('取消'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                              child: const Text('保存'),
                            ),
                          ],
                        ),
                      );
                      if (newName != null && newName.isNotEmpty) {
                        await wc.renameActiveWallet(newName);
                      }
                    },
                    icon: const Icon(Icons.edit, color: AppColors.textPrimary),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        '我的钱包',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: AppColors.textMuted, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: '搜索',
                          hintStyle: TextStyle(color: AppColors.textMuted),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '软件钱包',
                  style: TextStyle(color: AppColors.textSecondary.withOpacity(0.9), fontSize: 12),
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: items.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          '暂无钱包，点击下方添加',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                        ),
                      )
                    : SingleChildScrollView(
                  child: Column(
                    children: items.map((w) {
                      final selected = w.id == widget.selectedId;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () {
                                    widget.onSelect(w.id);
                                    Navigator.of(context).pop();
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: AppColors.surfaceElevated,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Center(
                                            child: Container(
                                              width: 22,
                                              height: 22,
                                              decoration: BoxDecoration(
                                                border: Border.all(color: AppColors.textMuted, width: 2),
                                                borderRadius: BorderRadius.circular(5),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      w.name,
                                                      style: const TextStyle(
                                                        color: AppColors.textPrimary,
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (!w.backedUp) ...[
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      width: 8,
                                                      height: 8,
                                                      decoration: const BoxDecoration(
                                                        color: Colors.red,
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.surfaceElevated,
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: const Text(
                                                      '助记词',
                                                      style: TextStyle(
                                                        color: AppColors.textSecondary,
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  const Text(
                                                    'EVM',
                                                    style: TextStyle(
                                                      color: AppColors.textMuted,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (selected)
                                          Padding(
                                            padding: const EdgeInsets.only(right: 4),
                                            child: Container(
                                              width: 26,
                                              height: 26,
                                              decoration: const BoxDecoration(
                                                color: AppColors.success,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(Icons.check, size: 16, color: Colors.white),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => widget.onOpenWalletDetails(w),
                                icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: widget.onAddWallet,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.accentText,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add, size: 20),
                      SizedBox(width: 8),
                      Text('添加钱包'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
