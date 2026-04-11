import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'backup_method_screen.dart';

class BackupPromptScreen extends StatefulWidget {
  const BackupPromptScreen({super.key});

  @override
  State<BackupPromptScreen> createState() => _BackupPromptScreenState();
}

class _BackupPromptScreenState extends State<BackupPromptScreen> {
  bool _dontShowAgain = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary),
                  ),
                  const Spacer(),
                  const Text('ETH', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  const Spacer(),
                  const SizedBox(width: 44),
                ],
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 80),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.accent, width: 2),
                        ),
                        child: const Icon(Icons.error_outline, color: AppColors.textSecondary, size: 34),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '你的助记词还没备份。丢失助记词将会导致资产损失。我们强烈建议你在接收资产之前先备份一份助记词。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFFD4D4D8), fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _dontShowAgain,
                            onChanged: (v) => setState(() => _dontShowAgain = v ?? false),
                            side: const BorderSide(color: AppColors.borderSoft),
                            activeColor: AppColors.accent,
                            checkColor: Colors.black,
                          ),
                          const Text('不再提示。', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.textPrimary,
                                  side: const BorderSide(color: AppColors.borderSoft),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                child: const Text('跳过', style: TextStyle(fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: FilledButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const BackupMethodScreen()),
                                  );
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.accent,
                                  foregroundColor: AppColors.accentText,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                child: const Text('备份', style: TextStyle(fontWeight: FontWeight.w800)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

