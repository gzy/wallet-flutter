import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// 全屏后台模式页右上角：单胶囊内「…」|「−」|「×」三操作（对齐设计稿）。
class BackendFloatWindowCapsuleBar extends StatelessWidget {
  const BackendFloatWindowCapsuleBar({
    super.key,
    required this.onMore,
    required this.onMinimize,
    required this.onClose,
  });

  final VoidCallback onMore;
  final VoidCallback onMinimize;
  final VoidCallback onClose;

  static const Color _capsuleBg = Color(0xFF2C2C2E);
  static const Color _capsuleBorder = Color(0xFF4A4A4E);
  static const Color _divider = Color(0xFF5A5A5E);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: _capsuleBg.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _capsuleBorder, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CapsuleAction(
            onTap: onMore,
            child: const Icon(
              Icons.more_horiz,
              size: 16,
              color: AppColors.textPrimary,
            ),
          ),
          const _CapsuleDivider(),
          _CapsuleAction(
            onTap: onMinimize,
            child: const Icon(
              Icons.remove,
              size: 16,
              color: AppColors.textPrimary,
            ),
          ),
          const _CapsuleDivider(),
          _CapsuleAction(
            onTap: onClose,
            child: Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.textMuted,
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.close,
                size: 11,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapsuleDivider extends StatelessWidget {
  const _CapsuleDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 14,
      color: BackendFloatWindowCapsuleBar._divider,
    );
  }
}

class _CapsuleAction extends StatelessWidget {
  const _CapsuleAction({
    required this.onTap,
    required this.child,
  });

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: child,
        ),
      ),
    );
  }
}
