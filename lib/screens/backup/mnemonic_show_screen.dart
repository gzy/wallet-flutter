import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/wallet_controller.dart';
import '../../theme/app_colors.dart';
import 'mnemonic_verify_screen.dart';

class MnemonicShowScreen extends StatelessWidget {
  const MnemonicShowScreen({super.key, this.reviewOnly = false});

  /// 已备份用户仅查看助记词：底部为「完成」并返回，不再进入顺序验证页。
  final bool reviewOnly;

  @override
  Widget build(BuildContext context) {
    final future =
        context.read<WalletController>().readMnemonicForBackup().then((s) {
      if (s == null || s.trim().isEmpty) {
        throw StateError('未找到助记词');
      }
      return s.trim().split(RegExp(r'\s+'));
    });

    return FutureBuilder<List<String>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              backgroundColor: AppColors.background,
              title: const Text('备份'),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '无法加载助记词：${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
                child: CircularProgressIndicator(color: AppColors.accent)),
          );
        }
        final words = snapshot.data!;
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
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.schedule,
                            color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(26, 10, 26, 0),
                  child: Text(
                    '请按顺序抄写助记词，并妥善保存，未来可以通过助记词恢复此钱包。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.4),
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: words.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 2.25,
                    ),
                    itemBuilder: (context, i) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Text('${i + 1}',
                                style: const TextStyle(
                                    color: Color(0xFFA1A1AA), fontSize: 12)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                words[i],
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 22),
                  child: Column(
                    children: [
                      _TipRow(
                        icon: Icons.check_circle,
                        iconColor: AppColors.success,
                        title: '推荐：',
                        titleColor: AppColors.success,
                        body: '将它抄写在一张纸上并保存在安全的地方。',
                      ),
                      SizedBox(height: 12),
                      _AvoidRow(),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 22),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('了解更多助记词知识',
                        style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: () {
                        if (reviewOnly) {
                          Navigator.of(context).pop();
                          return;
                        }
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const MnemonicVerifyScreen()),
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.accentText,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        reviewOnly ? '完成' : '下一步',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TipRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Color titleColor;
  final String body;
  const _TipRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.titleColor,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 13, height: 1.35),
              children: [
                TextSpan(
                    text: title,
                    style: TextStyle(
                        color: titleColor, fontWeight: FontWeight.w800)),
                TextSpan(
                    text: body,
                    style: const TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AvoidRow extends StatelessWidget {
  const _AvoidRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.cancel, color: Colors.red, size: 20),
        SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('避免：',
                  style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w800,
                      fontSize: 13)),
              SizedBox(height: 4),
              Text('· 请勿截屏或者复制到剪切板。',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.35)),
              Text('· 请勿将助记词保存到网上。',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.35)),
              Text('· 请勿将助记词发给任何人。',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.35)),
            ],
          ),
        ),
      ],
    );
  }
}
