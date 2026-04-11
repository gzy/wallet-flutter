import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';

class WalletBalanceSection extends StatelessWidget {
  final bool isBalanceVisible;
  final double totalBalance;
  /// 有可靠 BTC 现货价与 USD 估值时再传入；为 null 时不展示 BTC 折算行（避免假价格）。
  final double? totalBtcEquivalent;
  final VoidCallback onToggleVisibility;

  const WalletBalanceSection({
    super.key,
    required this.isBalanceVisible,
    required this.totalBalance,
    required this.totalBtcEquivalent,
    required this.onToggleVisibility,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1A1A1A), width: 1)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('余额', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onToggleVisibility,
                child: Icon(
                  isBalanceVisible ? Icons.visibility : Icons.visibility_off,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isBalanceVisible ? '\$${totalBalance.toStringAsFixed(4)}' : '****',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 46,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (totalBtcEquivalent != null) ...[
            Text(
              isBalanceVisible ? '${totalBtcEquivalent!.toStringAsFixed(8)} BTC' : '****',
              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 2),
          ],
          const Text(
            '今日涨跌接入行情后显示',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
