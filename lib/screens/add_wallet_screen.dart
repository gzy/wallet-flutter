import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/wallet_controller.dart';
import '../theme/app_colors.dart';
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (sheetContext) => _PasswordSheet(
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

class _PasswordSheet extends StatefulWidget {
  const _PasswordSheet({required this.onSubmit});
  final Future<void> Function(String pin) onSubmit;

  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  String _pin = '';
  bool _busy = false;

  Future<void> _tap(String n) async {
    if (_pin.length >= 6 || _busy) return;
    setState(() => _pin = '$_pin$n');
    if (_pin.length != 6) return;

    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    try {
      await widget.onSubmit(_pin);
    } catch (_) {
      setState(() {
        _pin = '';
        _busy = false;
      });
      return;
    }
    if (mounted) setState(() => _busy = false);
  }

  void _delete() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Spacer(),
                  const Text(
                    '请输入安全密码',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(6, (i) {
                    final filled = i < _pin.length;
                    return Container(
                      width: 44,
                      height: 44,
                      margin: const EdgeInsets.symmetric(horizontal: 7),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: filled ? AppColors.textPrimary : AppColors.borderSoft,
                          width: 2,
                        ),
                        color: filled ? AppColors.textPrimary : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: filled
                          ? Center(
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Colors.black,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            )
                          : null,
                    );
                  }),
                ),
              ),
              _KeyRow(keys: const ['1', '2', '3'], onTap: _tap),
              const SizedBox(height: 10),
              _KeyRow(keys: const ['4', '5', '6'], onTap: _tap),
              const SizedBox(height: 10),
              _KeyRow(keys: const ['7', '8', '9'], onTap: _tap),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 88, height: 54),
                  _KeyButton(label: '0', onTap: () => _tap('0')),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 88,
                    height: 54,
                    child: TextButton(
                      onPressed: _delete,
                      style: TextButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Icon(Icons.backspace_outlined, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  final List<String> keys;
  final ValueChanged<String> onTap;
  const _KeyRow({required this.keys, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final k in keys) ...[
          _KeyButton(label: k, onTap: () => onTap(k)),
          if (k != keys.last) const SizedBox(width: 12),
        ]
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _KeyButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 88,
        height: 54,
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

