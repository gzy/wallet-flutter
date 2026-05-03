import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/recent_recipient.dart';
import '../models/stored_wallet.dart';
import '../providers/wallet_controller.dart';
import '../services/wallet/chain_rules.dart';
import '../theme/app_colors.dart';

/// 地址簿页与设计稿对齐的局部色（不改动全局 [AppColors]）。
const Color _addressBookTabAccent = Color(0xFF5D5FEF);
const Color _addressBookTabInactive = Color(0xFF8E8E93);
const Color _addressBookTabDivider = Color(0xFF3A3A3C);
const Color _addressBookEmptyIconCircle = Color(0xFF2C2C2E);

String _shortAddr(String hex) {
  final h = hex.trim();
  if (h.length < 18) {
    return h;
  }
  return '${h.substring(0, 16)}…${h.substring(h.length - 16)}';
}

String _shortAddrForChain(String addr, ChainKind kind) {
  final a = addr.trim();
  if (a.isEmpty) {
    return a;
  }
  switch (kind) {
    case ChainKind.tron:
    case ChainKind.solana:
    case ChainKind.xrp:
      if (a.length <= 18) {
        return a;
      }
      return '${a.substring(0, 10)}…${a.substring(a.length - 10)}';
    case ChainKind.evm:
    case ChainKind.unknown:
      return _shortAddr(a);
  }
}

String _chainKindChipLabel(ChainKind kind) {
  switch (kind) {
    case ChainKind.tron:
      return 'TRON';
    case ChainKind.solana:
      return 'SOL';
    case ChainKind.xrp:
      return 'XRP';
    case ChainKind.evm:
    case ChainKind.unknown:
      return 'EVM';
  }
}

/// 转账页进入的地址簿：最近（成功广播后写入）/ 我的钱包 / 保存的地址（占位）。
///
/// 从「我的钱包」选中一行可 [Navigator.pop] 带回当前链格式地址填入收款框（EVM / TRON / Solana）。
class AddressBookScreen extends StatefulWidget {
  const AddressBookScreen({
    super.key,
    required this.symbol,
    required this.networkLabel,
    required this.chainQuery,
  });

  /// 当前转账币种，用于「地址簿」空态提示。
  final String symbol;

  /// 当前所选网络展示名（如 Sepolia）。
  final String networkLabel;

  /// 与 `/api/app/wallet/*` 的 `chain` 一致，用于筛选「最近」记录。
  final String chainQuery;

  @override
  State<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends State<AddressBookScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kind = ChainRules.kindFromChainQuery(widget.chainQuery);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: const Text(
          '地址簿',
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.textPrimary, size: 26),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('添加地址功能开发中')),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _addressBookTabAccent,
          indicatorSize: TabBarIndicatorSize.label,
          indicatorWeight: 3,
          dividerColor: _addressBookTabDivider,
          dividerHeight: 1,
          labelColor: _addressBookTabAccent,
          unselectedLabelColor: _addressBookTabInactive,
          labelStyle: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2),
          unselectedLabelStyle: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.2),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          tabs: const [
            Tab(text: '最近'),
            Tab(text: '我的钱包'),
            Tab(text: '地址簿'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _RecentTab(
            networkLabel: widget.networkLabel,
            chainQuery: widget.chainQuery,
            chainKind: kind,
            onPickAddress: (hex) => Navigator.of(context).pop<String>(hex),
          ),
          _MyWalletsTab(
            networkLabel: widget.networkLabel,
            chainKind: kind,
            onPickAddress: (hex) => Navigator.of(context).pop<String>(hex),
          ),
          _SavedContactsTab(symbol: widget.symbol),
        ],
      ),
    );
  }
}

class _RecentTab extends StatefulWidget {
  const _RecentTab({
    required this.networkLabel,
    required this.chainQuery,
    required this.chainKind,
    required this.onPickAddress,
  });

  final String networkLabel;
  final String chainQuery;
  final ChainKind chainKind;
  final ValueChanged<String> onPickAddress;

  @override
  State<_RecentTab> createState() => _RecentTabState();
}

class _RecentTabState extends State<_RecentTab> {
  bool _loading = true;
  List<RecentRecipient> _items = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final wc = context.read<WalletController>();
    final list = await wc.recentRecipientsForChain(widget.chainQuery);
    if (!mounted) {
      return;
    }
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.accent,
          strokeWidth: 2,
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: _addressBookEmptyIconCircle,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.history,
                  size: 34,
                  color: _addressBookTabInactive,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '暂无最近转账地址',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '（${widget.networkLabel} · ${_chainKindChipLabel(widget.chainKind)}）',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted.withValues(alpha: 0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final r = _items[i];
        final addr = ChainRules.formatAddressForUi(widget.chainKind, r.address);
        return Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => widget.onPickAddress(addr),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(
                      Icons.history,
                      color: AppColors.textSecondary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _shortAddrForChain(addr, widget.chainKind),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _recentChip(widget.networkLabel),
                            _recentChip(_chainKindChipLabel(widget.chainKind)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _recentChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
      ),
    );
  }
}

class _MyWalletsTab extends StatelessWidget {
  const _MyWalletsTab({
    required this.networkLabel,
    required this.chainKind,
    required this.onPickAddress,
  });

  final String networkLabel;
  final ChainKind chainKind;
  final ValueChanged<String> onPickAddress;

  @override
  Widget build(BuildContext context) {
    final wc = context.watch<WalletController>();
    final wallets = wc.wallets;
    if (wallets.isEmpty) {
      return const Center(
        child: Text('暂无钱包', style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: wallets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final w = wallets[i];
        return _WalletAddressTile(
          wallet: w,
          networkLabel: networkLabel,
          chainKind: chainKind,
          onTap: onPickAddress,
        );
      },
    );
  }
}

class _WalletAddressTile extends StatefulWidget {
  const _WalletAddressTile({
    required this.wallet,
    required this.networkLabel,
    required this.chainKind,
    required this.onTap,
  });

  final StoredWallet wallet;
  final String networkLabel;
  final ChainKind chainKind;
  final ValueChanged<String> onTap;

  @override
  State<_WalletAddressTile> createState() => _WalletAddressTileState();
}

class _WalletAddressTileState extends State<_WalletAddressTile> {
  String? _addr;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final wc = context.read<WalletController>();
    final String? h;
    switch (widget.chainKind) {
      case ChainKind.tron:
        h = await wc.readTronAddressForWallet(widget.wallet.id);
        break;
      case ChainKind.solana:
        h = await wc.readSolanaAddressForWallet(widget.wallet.id);
        break;
      case ChainKind.xrp:
        h = await wc.readXrpAddressForWallet(widget.wallet.id);
        break;
      case ChainKind.evm:
      case ChainKind.unknown:
        h = await wc.readAddressHexForWallet(widget.wallet.id);
        break;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      if (h == null || h.isEmpty) {
        _addr = null;
      } else {
        final t = h.trim();
        _addr = switch (widget.chainKind) {
          ChainKind.evm ||
          ChainKind.unknown =>
            t.startsWith('0x') || t.startsWith('0X') ? t : '0x$t',
          ChainKind.tron || ChainKind.solana || ChainKind.xrp => t,
        };
      }
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
            child: CircularProgressIndicator(
                color: AppColors.accent, strokeWidth: 2)),
      );
    }
    final addr = _addr;
    if (addr == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '「${widget.wallet.name}」无法读取地址',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    }
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => widget.onTap(addr),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(Icons.account_balance_wallet_outlined,
                    color: AppColors.textSecondary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.wallet.name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _shortAddrForChain(addr, widget.chainKind),
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.35),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _chip(widget.networkLabel),
                        _chip(_chainKindChipLabel(widget.chainKind)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
    );
  }
}

class _SavedContactsTab extends StatelessWidget {
  const _SavedContactsTab({required this.symbol});

  final String symbol;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.find_in_page_outlined,
                size: 56, color: AppColors.textMuted.withValues(alpha: 0.55)),
            const SizedBox(height: 18),
            const Text(
              '没有当前币种可用的地址',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 8),
            Text(
              '当前：$symbol',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
