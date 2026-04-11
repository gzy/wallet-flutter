import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config/evm_environment.dart';
import '../models/evm_network.dart';
import '../providers/wallet_controller.dart';
import '../theme/app_colors.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  static const _receiveColors = {
    EvmNetworkId.ethereum: Color(0xFF6B7280),
    EvmNetworkId.base: Color(0xFF60A5FA),
  };

  late EvmNetworkId _receiveNetwork;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _receiveNetwork = EvmEnvironment.nativeCoins.first.networkKey;
  }

  List<_TokenOption> _tokenOptionsFor(WalletController w) {
    return EvmEnvironment.nativeCoins.map((cfg) {
      var bal = 0.0;
      final cid = EvmEnvironment.chainId(cfg.networkKey);
      for (final c in w.evmCoins) {
        if (c.chainId == cid) {
          bal = c.balance;
          break;
        }
      }
      return _TokenOption(
        networkKey: cfg.networkKey,
        symbol: cfg.symbol,
        network: cfg.networkLabel,
        balance: bal,
        color: _receiveColors[cfg.networkKey]!,
      );
    }).toList();
  }

  _TokenOption _currentToken(WalletController w) {
    final opts = _tokenOptionsFor(w);
    return opts.firstWhere(
      (o) => o.networkKey == _receiveNetwork,
      orElse: () => opts.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletController>();
    final address = wallet.addressHex;
    if (address == null) {
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

    final token = _currentToken(wallet);

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
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield, color: AppColors.textSecondary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${address.substring(0, 6)}…${address.substring(address.length - 4)}',
                        style: const TextStyle(color: AppColors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: () => _openTokenPicker(wallet),
                icon: const Icon(Icons.currency_exchange, color: AppColors.textPrimary),
                label: Text(
                  '${token.symbol} (${token.network})',
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: QrImageView(
                    data: address,
                    version: QrVersions.auto,
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                address,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.share),
                      label: const Text('分享'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: address));
                        setState(() => _copied = true);
                        Future.delayed(const Duration(seconds: 2), () {
                          if (mounted) setState(() => _copied = false);
                        });
                      },
                      icon: const Icon(Icons.copy),
                      label: Text(_copied ? '已复制' : '复制'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '该地址只接收 ${token.symbol} (${token.network}) 资产，请勿转入其它币种。',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
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
    final picked = await showModalBottomSheet<EvmNetworkId>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final all = _tokenOptionsFor(wallet);
            final filtered = all.where((t) {
              if (searchQuery.isEmpty) return true;
              final q = searchQuery.toLowerCase();
              return t.symbol.toLowerCase().contains(q) ||
                  t.network.toLowerCase().contains(q);
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
                        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
                      ),
                      child: Row(
                        children: [
                          const Spacer(),
                          const Text(
                            '选择币种',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: const Icon(Icons.close, color: AppColors.textSecondary),
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
                            const Icon(Icons.search, color: AppColors.textMuted),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                onChanged: (v) => setSheetState(() => searchQuery = v.trim()),
                                style: const TextStyle(fontSize: 16),
                                decoration: const InputDecoration(
                                  hintText: '搜索',
                                  hintStyle: TextStyle(color: AppColors.textMuted),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            const Text(
                              '粘贴',
                              style: TextStyle(
                                color: Color(0xFF22D3AA),
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
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
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            onTap: () => Navigator.pop(context, t.networkKey),
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundColor: t.color,
                              child: Text(
                                t.symbol.substring(0, 1),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            title: Text(
                              t.symbol,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              t.network,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                            trailing: Text(
                              t.balance == 0 ? '0' : t.balance.toStringAsFixed(8),
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
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
      setState(() => _receiveNetwork = picked);
    }
  }
}

class _TokenOption {
  final EvmNetworkId networkKey;
  final String symbol;
  final String network;
  final double balance;
  final Color color;
  const _TokenOption({
    required this.networkKey,
    required this.symbol,
    required this.network,
    required this.balance,
    required this.color,
  });
}
