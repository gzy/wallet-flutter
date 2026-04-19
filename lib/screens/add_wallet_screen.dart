import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/wallet_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/security_pin_bottom_sheet.dart';
import 'import_wallet_screen.dart';
import 'wallet_ready_screen.dart';

class AddWalletScreen extends StatefulWidget {
  const AddWalletScreen({super.key, this.openCreateDialogOnOpen = false});

  /// 欢迎页「创建钱包」进入时自动弹出创建确认，减少一步。
  final bool openCreateDialogOnOpen;

  @override
  State<AddWalletScreen> createState() => _AddWalletScreenState();
}

class _AddWalletScreenState extends State<AddWalletScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.openCreateDialogOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showCreateDialog();
      });
    }
  }

  void _showCreateDialog() {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (_) {
        return Dialog(
          backgroundColor: const Color(0xFF27272A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 22, 18, 18),
                child: Text(
                  '是否立即创建新钱包?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.borderSoft),
              _DialogAction(
                label: '立即创建',
                color: AppColors.accentText,
                onPressed: () {
                  Navigator.of(context).pop();
                  _showPasswordSheet();
                },
              ),
              const Divider(height: 1, color: AppColors.borderSoft),
              _DialogAction(
                label: '高级设置',
                color: AppColors.accentText,
                onPressed: () {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('高级设置开发中')),
                  );
                },
              ),
              const Divider(height: 1, color: AppColors.borderSoft),
              _DialogAction(
                label: '取消',
                color: Colors.red,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showPasswordSheet() async {
    final setupMode = !context.read<WalletController>().pinEnabled;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (sheetContext) => SecurityPinBottomSheet(
        setupMode: setupMode,
        onSubmit: (pin) async {
          final nav = Navigator.of(sheetContext);
          final messenger = ScaffoldMessenger.of(context);
          try {
            await context.read<WalletController>().createWallet(pin);
            if (!mounted) return;
            nav.pop();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WalletReadyScreen()),
            );
          } catch (e) {
            messenger.showSnackBar(SnackBar(content: Text('创建钱包失败: $e')));
            rethrow;
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 6, 22, 16),
              child: Text(
                '添加钱包',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                children: [
                  _OptionTile(
                    icon: Icons.add,
                    iconTint: const Color(0xFF60A5FA),
                    label: '创建新钱包',
                    onTap: _showCreateDialog,
                  ),
                  const SizedBox(height: 14),
                  _OptionTile(
                    icon: Icons.arrow_forward,
                    iconTint: const Color(0xFF22C55E),
                    label: '添加已有钱包',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ImportWalletScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  _OptionTile(
                    icon: Icons.link,
                    iconTint: const Color(0xFF60A5FA),
                    label: '连接硬件钱包',
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('连接硬件钱包开发中')),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _OptionTile(
                    icon: Icons.remove_red_eye_outlined,
                    iconTint: const Color(0xFF60A5FA),
                    label: '观察钱包',
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('观察钱包开发中')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final Color iconTint;
  final String label;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.iconTint,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.surface.withOpacity(0.55),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated.withOpacity(0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconTint, size: 22),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFD4D4D8),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogAction extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;
  const _DialogAction({required this.label, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: SizedBox(
        height: 52,
        width: double.infinity,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
