import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';

class WalletActionsRow extends StatelessWidget {
  final VoidCallback? onTransfer;
  final VoidCallback? onReceive;
  final VoidCallback? onBuy;
  final VoidCallback? onGas;
  final VoidCallback? onMore;

  const WalletActionsRow({
    super.key,
    this.onTransfer,
    this.onReceive,
    this.onBuy,
    this.onGas,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _ActionButton(icon: Icons.arrow_upward, label: '转账', onTap: onTransfer),
          _ActionButton(icon: Icons.arrow_downward, label: '收款', onTap: onReceive),
          _ActionButton(icon: Icons.credit_card, label: '买币', onTap: onBuy),
          _ActionButton(icon: Icons.local_gas_station, label: '加油站', onTap: onGas),
          _ActionButton(icon: Icons.more_horiz, label: '更多', onTap: onMore),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionButton({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(40),
      onTap: onTap,
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
            child: Icon(icon, size: 24, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
