import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/stored_wallet.dart';
import '../providers/wallet_controller.dart';
import '../theme/app_colors.dart';
import 'backup/backup_method_screen.dart';
import 'create_wallet_account_screen.dart';

/// 钱包详情（从「我的钱包」列表右侧 ⋮ 进入）
class WalletDetailScreen extends StatelessWidget {
  const WalletDetailScreen({super.key, required this.wallet});

  final StoredWallet wallet;

  static const Color _cardBg = Color(0xFF1E1E1E);

  static String _formatCreatedAtMs(int? ms) {
    if (ms == null) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  static String _securitySuffix(StoredWallet w) {
    final name = w.name;
    final i = name.lastIndexOf('-');
    if (i >= 0 && i < name.length - 1) {
      return name.substring(i + 1);
    }
    final compact = w.id.replaceAll('-', '');
    if (compact.length >= 3) {
      return compact.substring(compact.length - 3);
    }
    return compact;
  }

  String _tokenLine(BuildContext context) {
    final wc = context.watch<WalletController>();
    if (wallet.id != wc.activeWalletId) {
      return '≈ \$0';
    }
    final sum = wc.evmCoins.fold<double>(0, (a, c) => a + c.balanceUSD);
    if (sum == 0) {
      return '\$0';
    }
    return '≈ \$${sum.toStringAsFixed(2)}';
  }

  Future<void> _rename(BuildContext context) async {
    final wc = context.read<WalletController>();
    final ctrl = TextEditingController(text: wallet.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('修改钱包名称',
            style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: '名称',
            hintStyle: TextStyle(color: AppColors.textMuted),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('保存')),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && context.mounted) {
      await wc.renameWallet(wallet.id, newName);
    }
  }

  Future<void> _openBackup(BuildContext context) async {
    final wc = context.read<WalletController>();
    if (wc.activeWalletId != wallet.id) {
      await wc.switchWallet(wallet.id);
    }
    if (!context.mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BackupMethodScreen()),
    );
  }

  Future<void> _exportPublicKey(BuildContext context) async {
    final wc = context.read<WalletController>();
    final hex = await wc.readAddressHexForWallet(wallet.id);
    final tron = await wc.readTronAddressForWallet(wallet.id);
    if (!context.mounted) {
      return;
    }
    if ((hex == null || hex.isEmpty) && (tron == null || tron.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法读取该钱包地址')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('地址',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hex != null && hex.isNotEmpty) ...[
              const Text('EVM',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              SelectableText(
                hex.startsWith('0x') ? hex : '0x$hex',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13, height: 1.4),
              ),
            ],
            if (tron != null && tron.isNotEmpty) ...[
              if (hex != null && hex.isNotEmpty) const SizedBox(height: 14),
              const Text('TRON',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              SelectableText(
                tron,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13, height: 1.4),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              final text = (hex != null && hex.isNotEmpty)
                  ? (hex.startsWith('0x') ? hex : '0x$hex')
                  : (tron ?? '');
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制')),
              );
            },
            child: const Text('复制'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final wc = context.read<WalletController>();
    final match = wc.wallets.where((x) => x.id == wallet.id);
    final name = match.isEmpty ? wallet.name : match.first.name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title:
            const Text('删除钱包', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          '将移除「$name」及其本地助记词，且不可恢复。确定删除？',
          style: TextStyle(color: AppColors.textSecondary.withOpacity(0.95)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) {
      return;
    }
    await wc.deleteWallet(wallet.id);
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  void _suffixHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title:
            const Text('安全后缀', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          '从钱包名称中解析的简短标识，便于在多个钱包间区分；若名称中无「-」后缀，则使用钱包 ID 的片段。',
          style: TextStyle(color: AppColors.textSecondary, height: 1.45),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
        ],
      ),
    );
  }

  void _exportPubHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title:
            const Text('导出公钥', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          '此处展示由助记词派生的默认地址（EVM / TRON），可用于收款核对。完整扩展公钥展示与二维码导出可在后续版本提供。',
          style: TextStyle(color: AppColors.textSecondary, height: 1.45),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wc = context.watch<WalletController>();
    StoredWallet w = wallet;
    for (final x in wc.wallets) {
      if (x.id == wallet.id) {
        w = x;
        break;
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: AppColors.textPrimary, size: 20),
                  ),
                  const Expanded(
                    child: Text(
                      '钱包详情',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(
                            color: Color(0xFF2C2C2C),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.smartphone_outlined,
                              color: AppColors.textSecondary, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  w.name,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                onPressed: () => _rename(context),
                                icon: const Icon(Icons.edit_outlined,
                                    color: AppColors.textSecondary, size: 22),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    _Card(
                      child: Column(
                        children: [
                          const _InfoRow(
                            label: '创建方式',
                            value: '助记词',
                          ),
                          _divider(),
                          _InfoRow(
                            label: '创建时间',
                            value: _formatCreatedAtMs(w.createdAtMs),
                          ),
                          _divider(),
                          _InfoRow(
                            label: '安全后缀',
                            value: _securitySuffix(w),
                            trailingHint: true,
                            onHint: () => _suffixHelp(context),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Card(
                      child: Column(
                        children: [
                          _NavRow(
                            label: '备份',
                            onTap: () => _openBackup(context),
                          ),
                          _divider(),
                          _NavRow(
                            label: '导出公钥',
                            showHint: true,
                            onHint: () => _exportPubHelp(context),
                            onTap: () => _exportPublicKey(context),
                          ),
                          _divider(),
                          _NavRow(
                            label: '导出私钥',
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        '请通过「备份」导出助记词；私钥明文导出高风险，后续版本再开放。')),
                              );
                            },
                          ),
                          _divider(),
                          _NavRow(
                            label: '创建账户',
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      CreateWalletAccountScreen(wallet: w),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Card(
                      child: _InfoRow(
                        label: '代币',
                        value: _tokenLine(context),
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: () => _confirmDelete(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF4D4D),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          textStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        child: const Text('删除钱包'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _divider() =>
      const Divider(height: 1, thickness: 1, color: Color(0xFF2A2A2A));
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: WalletDetailScreen._cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.trailingHint = false,
    this.onHint,
  });

  final String label;
  final String value;
  final bool trailingHint;
  final VoidCallback? onHint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(color: Color(0xFF999999), fontSize: 14),
              ),
              if (trailingHint) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onHint,
                  child: const Icon(Icons.help_outline,
                      size: 16, color: Color(0xFF888888)),
                ),
              ],
            ],
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.label,
    required this.onTap,
    this.showHint = false,
    this.onHint,
  });

  final String label;
  final VoidCallback onTap;
  final bool showHint;
  final VoidCallback? onHint;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(label,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 15)),
                    if (showHint) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: onHint,
                        behavior: HitTestBehavior.opaque,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.help_outline,
                              size: 16, color: Color(0xFF888888)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppColors.textMuted, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
