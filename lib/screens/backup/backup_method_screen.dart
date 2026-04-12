import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/wallet_controller.dart';
import '../../theme/app_colors.dart';
import '../../widgets/pin_verify_sheet.dart';
import 'backup_password_screen.dart';
import 'mnemonic_show_screen.dart';

class BackupMethodScreen extends StatelessWidget {
  const BackupMethodScreen({super.key});

  /// iCloud 仅存在于 Apple 生态；Android 不应展示该入口。
  static bool get _showICloudBackupTile =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    final manualBackedUp = context.watch<WalletController>().backedUp;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        '备份',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '备份助记词',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 26),
              child: Text(
                '助记词是你的钱包的主Key。使用助记词可以在任何兼容的设备上恢复你的钱包。',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
              ),
            ),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  if (_showICloudBackupTile) ...[
                    _MethodTile(
                      icon: Icons.cloud_outlined,
                      title: '备份到 iCloud',
                      subtitle: '把备份文件保存到 iCloud。',
                      isBackupComplete: false,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('iCloud 备份流程暂未接入')),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  _MethodTile(
                    icon: Icons.description_outlined,
                    title: '手动备份',
                    subtitle: '自己保管助记词。',
                    isBackupComplete: manualBackedUp,
                    onTap: () => _openManualBackup(context, manualBackedUp),
                  ),
                ],
              ),
            ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Text(
                '了解更多助记词知识  查看',
                style: TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 未备份：进入设置备份密码与首次展示流程；已备份：先验 PIN 再直接进入助记词页。
Future<void> _openManualBackup(BuildContext context, bool manualBackedUp) async {
  if (!manualBackedUp) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const BackupPasswordScreen()),
    );
    return;
  }
  final wc = context.read<WalletController>();
  final ok = await PinVerifySheet.show(
    context,
    title: '验证 PIN',
    subtitle: '请输入 6 位 PIN 以查看助记词。',
    verify: wc.verifyTransactionPin,
  );
  if (!context.mounted || ok != true) {
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => const MnemonicShowScreen(reviewOnly: true),
    ),
  );
}

class _MethodTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  /// 是否已完成该方式的备份（手动备份与 [WalletController.backedUp] 同步；iCloud 未接入时为 false）。
  final bool isBackupComplete;
  final VoidCallback onTap;

  const _MethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isBackupComplete,
    required this.onTap,
  });

  static const Color _completeGreen = Color(0xFF34C759);
  static const Color _incompleteRed = Color(0xFFFF3B30);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            _BackupStatusDot(complete: isBackupComplete),
          ],
        ),
      ),
    );
  }
}

/// 与参考设计一致：已完成为绿底白勾，未完成为红底白叉。
class _BackupStatusDot extends StatelessWidget {
  const _BackupStatusDot({required this.complete});

  final bool complete;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: complete ? _MethodTile._completeGreen : _MethodTile._incompleteRed,
        shape: BoxShape.circle,
      ),
      child: Icon(
        complete ? Icons.check : Icons.close,
        color: Colors.white,
        size: 14,
      ),
    );
  }
}

