import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';

class WalletHeader extends StatelessWidget {
  const WalletHeader({
    super.key,
    required this.walletName,
    this.onOpenWalletManager,
    this.onOpenSettings,
    this.onOpenNotifications,
  });
  final String walletName;
  final VoidCallback? onOpenWalletManager;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenNotifications;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _IconBtn(
            icon: Icons.settings,
            onPressed: onOpenSettings,
          ),
          Expanded(
            child: Center(
              child: TextButton(
                onPressed: onOpenWalletManager,
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      walletName,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.textPrimary),
                  ],
                ),
              ),
            ),
          ),
          _NotificationBtn(onPressed: onOpenNotifications),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _IconBtn({required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed ?? () {},
      icon: Icon(icon, size: 20, color: AppColors.textSecondary),
      style: IconButton.styleFrom(
        minimumSize: const Size(34, 34),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _NotificationBtn extends StatelessWidget {
  final VoidCallback? onPressed;
  const _NotificationBtn({this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed ?? () {},
      style: IconButton.styleFrom(
        minimumSize: const Size(34, 34),
        padding: EdgeInsets.zero,
      ),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications, size: 20, color: AppColors.textSecondary),
          Positioned(
            right: -1,
            top: -1,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
