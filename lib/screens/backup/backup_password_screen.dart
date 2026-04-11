import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/wallet_controller.dart';
import '../../services/wallet/local_backup_service.dart';
import '../../theme/app_colors.dart';
import 'mnemonic_show_screen.dart';

class BackupPasswordScreen extends StatefulWidget {
  const BackupPasswordScreen({super.key});

  @override
  State<BackupPasswordScreen> createState() => _BackupPasswordScreenState();
}

class _BackupPasswordScreenState extends State<BackupPasswordScreen> {
  final TextEditingController _pwd = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _showPwd = false;
  bool _showConfirm = false;
  final List<bool> _checked = [false, false, false];

  @override
  void dispose() {
    _pwd.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _isValid => _pwd.text.length >= 8 && _pwd.text == _confirm.text;

  Future<void> _showWarningSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (_) {
        final localChecked = List<bool>.from(_checked);
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              top: false,
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Text(
                            '请务必牢记',
                            style: TextStyle(
                                color: Colors.red,
                                fontSize: 16,
                                fontWeight: FontWeight.w800),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close,
                                color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _CheckRow(
                        checked: localChecked[0],
                        text: '助记词一旦丢失会导致钱包账户资产丢失，无法找回。',
                        onToggle: () => setModalState(
                            () => localChecked[0] = !localChecked[0]),
                      ),
                      const SizedBox(height: 10),
                      _CheckRow(
                        checked: localChecked[1],
                        text: '卸载APP后，助记词将被永远删除。',
                        onToggle: () => setModalState(
                            () => localChecked[1] = !localChecked[1]),
                      ),
                      const SizedBox(height: 10),
                      _CheckRow(
                        checked: localChecked[2],
                        text: '请确保在四周无人，无摄像头的安全环境下备份助记词。',
                        onToggle: () => setModalState(
                            () => localChecked[2] = !localChecked[2]),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          onPressed: localChecked.every((e) => e)
                              ? () async {
                                  final messenger =
                                      ScaffoldMessenger.of(context);
                                  final w = context.read<WalletController>();
                                  final m = await w.readMnemonicForBackup();
                                  final id = w.activeWalletId;
                                  if (m == null || id == null) {
                                    messenger.showSnackBar(
                                      const SnackBar(
                                          content: Text('无法读取当前钱包助记词')),
                                    );
                                    return;
                                  }
                                  try {
                                    final path = await LocalBackupService
                                        .writeEncryptedBackup(
                                      mnemonic: m,
                                      backupPassword: _pwd.text,
                                      walletId: id,
                                    );
                                    messenger.showSnackBar(
                                      SnackBar(content: Text('已加密保存到本地：$path')),
                                    );
                                  } catch (e) {
                                    messenger.showSnackBar(
                                      SnackBar(content: Text('备份写入失败：$e')),
                                    );
                                    return;
                                  }
                                  if (!context.mounted) return;
                                  setState(() {
                                    _checked
                                      ..clear()
                                      ..addAll(localChecked);
                                  });
                                  Navigator.of(context).pop();
                                  if (!context.mounted) return;
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            const MnemonicShowScreen()),
                                  );
                                }
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: AppColors.accentText,
                            disabledBackgroundColor: AppColors.surfaceElevated,
                            disabledForegroundColor: AppColors.textMuted,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('立即备份',
                              style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: AppColors.textPrimary),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        '备份',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: const LinearGradient(
                      colors: [Color(0xFF8B5CF6), Color(0xFF2563EB)]),
                ),
                child: const Icon(Icons.cloud_upload_outlined,
                    color: Colors.white, size: 40),
              ),
              const SizedBox(height: 16),
              const Text(
                '创建备份密码',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                '设置备份密码，用于加密保存到本机的备份文件。恢复时需使用该密码解密。我们无法替你重置该密码。',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pwd,
                      obscureText: !_showPwd,
                      keyboardType: TextInputType.visiblePassword,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '输入备份密码',
                        hintStyle: const TextStyle(color: AppColors.textMuted),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: () => setState(() => _showPwd = !_showPwd),
                    icon: Icon(
                        _showPwd ? Icons.visibility_off : Icons.visibility,
                        color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _confirm,
                      obscureText: !_showConfirm,
                      keyboardType: TextInputType.visiblePassword,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '确认密码',
                        hintStyle: const TextStyle(color: AppColors.textMuted),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: _confirm.text.isEmpty
                              ? BorderSide.none
                              : BorderSide(
                                  color: _isValid
                                      ? Colors.transparent
                                      : AppColors.accent,
                                  width: 1.5),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: _confirm.text.isEmpty
                              ? BorderSide.none
                              : BorderSide(
                                  color: _isValid
                                      ? Colors.transparent
                                      : AppColors.accent,
                                  width: 1.5),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: () =>
                        setState(() => _showConfirm = !_showConfirm),
                    icon: Icon(
                        _showConfirm ? Icons.visibility_off : Icons.visibility,
                        color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('密码必须是至少8位，包含字母和数字。',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          color: AppColors.textMuted, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '备份文件仅保存在本应用文档目录，已用你设置的密码加密。请自行妥善保管该文件与密码。',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _isValid ? _showWarningSheet : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.accentText,
                    disabledBackgroundColor: AppColors.surfaceElevated,
                    disabledForegroundColor: AppColors.textMuted,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('下一步',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final bool checked;
  final String text;
  final VoidCallback onToggle;
  const _CheckRow(
      {required this.checked, required this.text, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: checked ? AppColors.success : AppColors.surfaceElevated,
              shape: BoxShape.circle,
            ),
            child: checked
                ? const Icon(Icons.check, size: 16, color: Colors.black)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.35))),
        ],
      ),
    );
  }
}
