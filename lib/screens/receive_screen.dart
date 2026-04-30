import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/coin_data.dart';
import '../providers/wallet_controller.dart';
import '../services/wallet/chain_rules.dart';
import '../theme/app_colors.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key, this.initialChain});

  /// 进入时默认选中的后端 `chain` 查询参数（如 ETH/BSC/TRX）；为空则使用当前全局筛选 [WalletController.sendChain]。
  final String? initialChain;

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  static const _receiveAccentColors = <Color>[
    Color(0xFF6B7280),
    Color(0xFF60A5FA),
    Color(0xFF22D3AA),
    Color(0xFFF59E0B),
    Color(0xFFA78BFA),
  ];

  String? _receiveChain;
  bool _copied = false;
  final GlobalKey _shareButtonKey = GlobalKey();

  Color _accentForCoin(CoinData c) {
    final k = c.chainId ?? c.id.hashCode;
    return _receiveAccentColors[k.abs() % _receiveAccentColors.length];
  }

  Rect _sharePositionRect() {
    final ctx = _shareButtonKey.currentContext;
    if (ctx != null) {
      final box = ctx.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        final topLeft = box.localToGlobal(Offset.zero);
        final sz = box.size;
        if (sz.width >= 1 && sz.height >= 1) {
          return topLeft & sz;
        }
      }
    }
    final m = MediaQuery.sizeOf(context);
    return Rect.fromCenter(
      center: Offset(m.width / 2, m.height / 2),
      width: 48,
      height: 48,
    );
  }

  Future<void> _shareAddress(String address) async {
    await Share.share(
      address,
      subject: '收款地址',
      sharePositionOrigin: _sharePositionRect(),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final w = context.read<WalletController>();
      setState(() {
        _receiveChain = widget.initialChain ?? w.sendChain;
      });
    });
  }

  String _titleLineForCoin(CoinData c) {
    final sym = c.symbol;
    final net = (c.network ?? '').trim();
    final name = c.name.trim();
    if (net.isEmpty) {
      return sym;
    }
    if (name.isNotEmpty && name.toUpperCase() != sym.toUpperCase()) {
      return '$sym ($name · $net)';
    }
    return '$sym ($net)';
  }

  List<_TokenOption> _tokenOptionsFor(WalletController w) {
    final out = <_TokenOption>[];
    for (final c in w.evmCoins) {
      out.add(
        _TokenOption(
          chain: w.chainParamForCoin(c),
          symbol: c.symbol,
          network: c.network ?? '—',
          titleLine: _titleLineForCoin(c),
          balance: c.balance,
          color: _accentForCoin(c),
        ),
      );
    }
    return out;
  }

  _TokenOption _currentToken(WalletController w) {
    final opts = _tokenOptionsFor(w);
    if (opts.isEmpty) {
      throw StateError('no token options');
    }
    final want = _receiveChain;
    if (want == null) {
      return opts.first;
    }
    return opts.firstWhere(
      (o) => o.chain == want,
      orElse: () => opts.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletController>();
    final evmAddress = wallet.addressHex;
    final tronAddress = wallet.tronAddress;
    if (evmAddress == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: const Text('收款', style: TextStyle(fontSize: 18)),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '请先创建或导入钱包',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }

    if (wallet.evmCoins.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: const Text('收款', style: TextStyle(fontSize: 18)),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '暂无可收款资产：请确认 /api/app/chains 已返回链配置且余额接口可用。',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
            ),
          ),
        ),
      );
    }

    final token = _currentToken(wallet);
    final cfg = wallet.backendChains.firstWhere(
      (c) => c.walletApiChainQuery == token.chain,
      orElse: () => wallet.backendChains.first,
    );
    final kind = ChainRules.kindFromChainType(cfg.chainType);
    final address = kind == ChainKind.tron ? tronAddress : evmAddress;
    if (address == null || address.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: const Text('收款', style: TextStyle(fontSize: 18)),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '收款地址不可用',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }
    final walletTitle = (wallet.activeWallet?.name ?? '').trim();
    final addrShort = address.length > 12
        ? '${address.substring(0, 6)}…${address.substring(address.length - 4)}'
        : address;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: const Text('收款', style: TextStyle(fontSize: 18)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.smartphone_outlined,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        walletTitle.isNotEmpty ? walletTitle : addrShort,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1D24),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _openTokenPicker(wallet),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 4,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 48,
                                height: 48,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Positioned(
                                      left: 0,
                                      top: 0,
                                      child: CircleAvatar(
                                        radius: 22,
                                        backgroundColor: token.color,
                                        child: Text(
                                          token.symbol.isNotEmpty
                                              ? token.symbol[0]
                                              : '?',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      right: -2,
                                      bottom: -2,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0F1014),
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          border: Border.all(
                                            color: AppColors.borderSoft,
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Text(
                                          ChainRules.badgeLabel(kind),
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            height: 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  token.titleLine,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: AppColors.textSecondary,
                                size: 26,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(10),
                          child: SizedBox(
                            width: 204,
                            height: 204,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                QrImageView(
                                  data: address,
                                  version: QrVersions.auto,
                                  size: 204,
                                  padding: EdgeInsets.zero,
                                  backgroundColor: Colors.white,
                                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                                  eyeStyle: const QrEyeStyle(
                                    eyeShape: QrEyeShape.square,
                                    color: Color(0xFF111111),
                                  ),
                                  dataModuleStyle: const QrDataModuleStyle(
                                    dataModuleShape: QrDataModuleShape.square,
                                    color: Color(0xFF111111),
                                  ),
                                ),
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.12),
                                        blurRadius: 6,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    ChainRules.badgeLabel(kind),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF374151),
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      address,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      key: _shareButtonKey,
                      height: 50,
                      child: OutlinedButton(
                        onPressed: () => _shareAddress(address),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          backgroundColor: AppColors.surface,
                          side: const BorderSide(
                            color: AppColors.borderSoft,
                            width: 1.2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.share_outlined, size: 20),
                            SizedBox(width: 8),
                            Text(
                              '分享',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: FilledButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: address));
                          setState(() => _copied = true);
                          Future.delayed(const Duration(seconds: 2), () {
                            if (mounted) {
                              setState(() => _copied = false);
                            }
                          });
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.accentText,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.copy_outlined,
                              size: 20,
                              color: AppColors.accentText,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _copied ? '已复制' : '复制',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderSoft, width: 1),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: AppColors.textMuted,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            height: 1.45,
                          ),
                          children: [
                            const TextSpan(text: '该地址只接收 '),
                            TextSpan(
                              text: token.titleLine,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const TextSpan(text: ' 资产，请勿转入其它币种。'),
                          ],
                        ),
                      ),
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

  Future<void> _openTokenPicker(WalletController wallet) async {
    String searchQuery = '';
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final all = _tokenOptionsFor(wallet);
            final filtered = all.where((t) {
              if (searchQuery.isEmpty) {
                return true;
              }
              final q = searchQuery.toLowerCase();
              return t.symbol.toLowerCase().contains(q) ||
                  t.network.toLowerCase().contains(q) ||
                  t.titleLine.toLowerCase().contains(q);
            }).toList();
            return SafeArea(
              top: false,
              child: Container(
                height: MediaQuery.of(context).size.height * 0.83,
                decoration: const BoxDecoration(
                  color: Color(0xFF14161D),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                      decoration: const BoxDecoration(
                        border: Border(
                            bottom:
                                BorderSide(color: AppColors.border, width: 1)),
                      ),
                      child: Row(
                        children: [
                          const Spacer(),
                          const Text(
                            '选择币种',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: const Icon(Icons.close,
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF23252D),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.search,
                                color: AppColors.textMuted),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                onChanged: (v) =>
                                    setSheetState(() => searchQuery = v.trim()),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w400,
                                ),
                                decoration: const InputDecoration(
                                  hintText: '搜索',
                                  hintStyle:
                                      TextStyle(color: AppColors.textMuted),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            const Text(
                              '粘贴',
                              style: TextStyle(
                                color: Color(0xFF22D3AA),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: AppColors.border),
                        itemBuilder: (context, index) {
                          final t = filtered[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            onTap: () => Navigator.pop(context, t.chain),
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundColor: t.color,
                              child: Text(
                                t.symbol.substring(0, 1),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            title: Text(
                              t.symbol,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            subtitle: Text(
                              t.network,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            trailing: Text(
                              t.balance == 0
                                  ? '0'
                                  : t.balance.toStringAsFixed(8),
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (picked != null) {
      setState(() => _receiveChain = picked);
    }
  }
}

class _TokenOption {
  final String chain;
  final String symbol;
  final String network;

  /// 主卡片展示，如 `ETH (Ethereum Sepolia)`。
  final String titleLine;
  final double balance;
  final Color color;
  const _TokenOption({
    required this.chain,
    required this.symbol,
    required this.network,
    required this.titleLine,
    required this.balance,
    required this.color,
  });
}
