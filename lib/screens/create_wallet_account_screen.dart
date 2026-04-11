import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/stored_wallet.dart';
import '../providers/wallet_controller.dart';
import '../theme/app_colors.dart';

/// 从钱包详情进入的「创建账户」页（EVM 子账户命名占位，链上派生待接入）。
class CreateWalletAccountScreen extends StatefulWidget {
  const CreateWalletAccountScreen({super.key, required this.wallet});

  final StoredWallet wallet;

  @override
  State<CreateWalletAccountScreen> createState() => _CreateWalletAccountScreenState();
}

class _CreateWalletAccountScreenState extends State<CreateWalletAccountScreen> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    final idx = context.read<WalletController>().wallets.indexWhere((w) => w.id == widget.wallet.id);
    final n = idx >= 0 ? idx + 2 : 2;
    _nameCtrl = TextEditingController(text: '${widget.wallet.name}#$n');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary, size: 20),
                  ),
                  const Expanded(
                    child: Text(
                      '创建账户',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 24),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '命名你的账户',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nameCtrl,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.borderSoft),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('取消', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('多账户派生与链上索引开发中')),
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.accentText,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('创建', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text(
                '提示：\n'
                '1. 将根据您钱包 \'${widget.wallet.name}\' 的扩展公钥生成一个新账户。\n'
                '2. 此类账户只能管理 EVM 网络上的资产，如以太坊、BNB 智能链、AVAX C-Chain 等。',
                style: TextStyle(
                  color: AppColors.textMuted.withOpacity(0.95),
                  fontSize: 12,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
