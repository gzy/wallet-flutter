import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'backend_float_config.dart';
import 'backend_float_controller.dart';

/// 后台模式悬浮窗通用「…」菜单：单按钮切换模块浮窗开关（持久化）。
abstract final class BackendFloatMenu {
  BackendFloatMenu._();

  static void show(
    BuildContext context, {
    required BackendFloatController controller,
    required BackendFloatConfig config,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final enabled = controller.floatEnabled;
          return SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(
                    enabled
                        ? Icons.bubble_chart_outlined
                        : Icons.picture_in_picture_alt_outlined,
                    color: AppColors.textPrimary,
                  ),
                  title: Text(
                    enabled ? '取消浮窗' : '浮窗',
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await controller.toggleFloatFromMenu();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }
}
