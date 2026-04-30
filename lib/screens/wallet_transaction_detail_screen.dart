import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/chain_transaction_vo.dart';
import '../models/coin_data.dart';
import '../services/wallet/chain_rules.dart';
import '../theme/app_colors.dart';
import '../widgets/coin_icon.dart';
import 'transfer_screen.dart';

/// 与列表页一致的数量展示（避免过长小数）。
String _formatDetailQuantity(double? q) {
  if (q == null) {
    return '—';
  }
  if (q == 0) {
    return '0';
  }
  final v = q.abs();
  if (v >= 1) {
    return q
        .toStringAsFixed(5)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
  return q
      .toStringAsFixed(8)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String _formatMinerFee(double? fee, String? feeCrypto) {
  if (fee == null) {
    return '—';
  }
  final sym = (feeCrypto ?? '').trim();
  final s = _formatDetailQuantity(fee);
  if (sym.isEmpty) {
    return s;
  }
  return '$s $sym';
}

String _formatFullDateTime(DateTime? t) {
  if (t == null) {
    return '—';
  }
  final x = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${x.year}-${two(x.month)}-${two(x.day)} ${two(x.hour)}:${two(x.minute)}:${two(x.second)}';
}

String _midTruncHash(String hash, {required bool isTron}) {
  final raw = hash.trim();
  final h = isTron ? raw : (raw.startsWith('0x') ? raw : '0x$raw');
  if (h.length <= 22) {
    return h;
  }
  return '${h.substring(0, 8)}…${h.substring(h.length - 8)}';
}

bool _txOutgoing(
  ChainTransactionVo tx,
  String? walletAddress, {
  required bool isTron,
}) {
  final fd = tx.fundDirection?.toLowerCase().trim();
  if (fd == 'out' || fd == 'send' || fd == 'outgoing') {
    return true;
  }
  if (fd == 'in' || fd == 'receive' || fd == 'incoming') {
    return false;
  }
  final w = _normWalletAddr(walletAddress, isTron: isTron);
  if (w.isEmpty) {
    return false;
  }
  final from = _normAddr(tx.fromAddress, isTron: isTron);
  final to = _normAddr(tx.toAddress, isTron: isTron);
  if (from == w && to != w) {
    return true;
  }
  if (to == w && from != w) {
    return false;
  }
  return false;
}

String _normWalletAddr(String? raw, {required bool isTron}) {
  if (raw == null) {
    return '';
  }
  final s = raw.trim();
  if (s.isEmpty) {
    return '';
  }
  if (isTron) {
    return s;
  }
  final x = s.toLowerCase();
  return x.startsWith('0x') ? x : '0x$x';
}

String _normAddr(String? raw, {required bool isTron}) {
  if (raw == null) {
    return '';
  }
  final s = raw.trim();
  if (s.isEmpty) {
    return '';
  }
  if (isTron) {
    return s;
  }
  final x = s.toLowerCase();
  return x.startsWith('0x') ? x : '0x$x';
}

/// 后端 `status`：0 / 1 视为链上成功态（与设计稿「交易成功」一致）。
String _statusDisplayLabel(int? status) {
  if (status == null) {
    return '—';
  }
  if (status == 0 || status == 1) {
    return '交易成功';
  }
  return '状态 $status';
}

Color _statusValueColor(int? status) {
  if (status == null) {
    return AppColors.textSecondary;
  }
  if (status == 0 || status == 1) {
    return AppColors.success;
  }
  return AppColors.error;
}

String? _counterpartyAddress(ChainTransactionVo d) {
  final fd = d.fundDirection?.toLowerCase().trim();
  if (fd == 'in' || fd == 'receive' || fd == 'incoming') {
    final a = d.fromAddress?.trim();
    return (a != null && a.isNotEmpty) ? a : null;
  }
  if (fd == 'out' || fd == 'send' || fd == 'outgoing') {
    final a = d.toAddress?.trim();
    return (a != null && a.isNotEmpty) ? a : null;
  }
  final to = d.toAddress?.trim();
  final from = d.fromAddress?.trim();
  if (to != null && to.isNotEmpty) {
    return to;
  }
  if (from != null && from.isNotEmpty) {
    return from;
  }
  return null;
}

String _protocolSubtitle(ChainTransactionVo d, String symbolFallback) {
  final p = d.protocol?.trim();
  if (p != null && p.isNotEmpty) {
    return p;
  }
  final c = d.contractAddress?.trim();
  if (c != null && c.isNotEmpty) {
    return 'ERC20';
  }
  return d.crypto?.trim().isNotEmpty == true
      ? d.crypto!.trim()
      : symbolFallback;
}

Uri? _txExplorerUri(ChainTransactionVo detail, CoinData coin, String rawHash) {
  final link = detail.txLink?.trim();
  if (link != null && link.isNotEmpty) {
    return Uri.tryParse(link);
  }
  final isTron =
      ChainRules.kindFromChainQuery(coin.walletApiChainQuery) == ChainKind.tron;
  final raw = rawHash.trim();
  final h = isTron ? raw : (raw.startsWith('0x') ? raw : '0x$raw');
  final p = coin.txUrlPrefix?.trim();
  if (p == null || p.isEmpty) {
    return null;
  }
  final b = p.endsWith('/') ? p : '$p/';
  return Uri.tryParse('$b$h');
}

/// 钱包 API 交易详情（全屏，与设计稿一致）。
class WalletTransactionDetailScreen extends StatelessWidget {
  const WalletTransactionDetailScreen({
    super.key,
    required this.detail,
    required this.coin,
    required this.rawTxHash,
    this.walletHex,
  });

  final ChainTransactionVo detail;
  final CoinData coin;
  final String rawTxHash;
  final String? walletHex;

  static const _cardRadius = 12.0;

  /// 详情卡片左侧标签灰（略亮于 [AppColors.textMuted]，贴近参考稿）。
  static const _labelGray = Color(0xFF8E8E93);

  /// Hash 与复制图标用蓝链色（与参考截图一致）。
  static const _txLinkBlue = Color(0xFF5B9FFF);

  /// 底部主按钮描边深蓝紫（参考约 `#2E3092`）。
  static const _bottomBtnBorder = Color(0xFF2E3092);

  Future<void> _copy(BuildContext context, String text) async {
    final t = text.trim();
    if (t.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: t));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制')),
      );
    }
  }

  Future<void> _openExplorerTx(BuildContext context) async {
    final hash = (detail.txHash ?? rawTxHash).trim();
    if (hash.isEmpty) {
      return;
    }
    final uri = _txExplorerUri(detail, coin, hash);
    if (uri == null) {
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isTron = ChainRules.kindFromChainQuery(coin.walletApiChainQuery) ==
        ChainKind.tron;
    final outgoing = _txOutgoing(detail, walletHex, isTron: isTron);
    final title = outgoing ? '转出' : '收款';
    final sym = detail.crypto?.trim().isNotEmpty == true
        ? detail.crypto!.trim()
        : coin.symbol;
    final qty = detail.quantity;
    final amtStr = _formatDetailQuantity(qty);
    final sign = outgoing ? '-' : '+';
    final st = detail.status;
    final stLabel = _statusDisplayLabel(st);
    final stColor = _statusValueColor(st);
    final from = detail.fromAddress?.trim() ?? '';
    final to = detail.toAddress?.trim() ?? '';
    final hash = (detail.txHash ?? rawTxHash).trim();
    final counterparty = _counterpartyAddress(detail);
    final canTransfer = counterparty != null &&
        counterparty.isNotEmpty &&
        _normAddr(counterparty, isTron: isTron) !=
            _normWalletAddr(walletHex, isTron: isTron);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leadingWidth: 56,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '交易详情',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),

        /// 与 [leading] 同宽，保证标题相对屏幕水平居中（参考设计稿）。
        actions: const [
          SizedBox(width: 56, height: 56),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _amountCard(sign, amtStr, sym),
                  const SizedBox(height: 12),
                  _statusCard(stLabel, stColor),
                  const SizedBox(height: 12),
                  _addressCard(context, from, to),
                  const SizedBox(height: 12),
                  _chainCard(context, hash, isTron: isTron),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: !canTransfer
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => TransferScreen(
                                initialRecipientAddress: counterparty,
                                initialChain: coin.walletApiChainQuery,
                              ),
                            ),
                          );
                        },
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: AppColors.textPrimary,
                    disabledForegroundColor: AppColors.textMuted,
                    side: BorderSide(
                      color:
                          canTransfer ? _bottomBtnBorder : AppColors.borderSoft,
                      width: 1.2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  child: const Text(
                    '转账给他/她',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountCard(String sign, String amt, String sym) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Row(
        children: [
          CoinIcon(symbol: coin.symbol, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$sign$amt $sym',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _protocolSubtitle(detail, sym),
                  style: const TextStyle(
                    color: _labelGray,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(String stLabel, Color stColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Column(
        children: [
          _kvRow(
            '状态',
            stLabel,
            valueColor: stColor,
          ),
          const SizedBox(height: 12),
          _kvRow(
            '矿工费',
            _formatMinerFee(detail.transactionFee, detail.feeCrypto),
          ),
          const SizedBox(height: 12),
          _kvRow('时间', _formatFullDateTime(detail.transactionTime)),
        ],
      ),
    );
  }

  Widget _kvRow(String label, String value, {Color? valueColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _labelGray,
            fontSize: 14,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: valueColor ?? AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _addressCard(BuildContext context, String from, String to) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _addressBlock(
            context,
            label: '付款地址',
            address: from,
            showAddContact: true,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, color: AppColors.borderSoft),
          ),
          _addressBlock(
            context,
            label: '收款地址',
            address: to,
            showAddContact: false,
          ),
        ],
      ),
    );
  }

  Widget _addressBlock(
    BuildContext context, {
    required String label,
    required String address,
    required bool showAddContact,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: _labelGray,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            if (showAddContact)
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: const Icon(
                  Icons.person_add_alt_1_outlined,
                  color: _txLinkBlue,
                  size: 22,
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('添加联系人功能开发中')),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText(
                address.isEmpty ? '—' : address,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 1),
              child: _topAlignedIconButton(
                context: context,
                icon: Icons.copy_outlined,
                color: _txLinkBlue,
                onPressed:
                    address.isEmpty ? null : () => _copy(context, address),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _chainCard(BuildContext context, String hash, {required bool isTron}) {
    final block = detail.blockNumber?.trim() ?? '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(
                width: 124,
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Transaction\u00A0Hash',
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: _labelGray,
                      fontSize: 14,
                      height: 1.2,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: hash.isEmpty
                              ? null
                              : () => _openExplorerTx(context),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 4, horizontal: 2),
                            child: Text(
                              hash.isEmpty
                                  ? '—'
                                  : _midTruncHash(hash, isTron: isTron),
                              textAlign: TextAlign.end,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _txLinkBlue,
                                fontSize: 14,
                                height: 1.2,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: hash.isEmpty ? null : () => _copy(context, hash),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 4, 2, 4),
                          child: Icon(
                            Icons.copy_outlined,
                            size: 20,
                            color: hash.isEmpty
                                ? _txLinkBlue.withValues(alpha: 0.35)
                                : _txLinkBlue,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(
                width: 118,
                child: Text(
                  'Block',
                  style: TextStyle(
                    color: _labelGray,
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  block.isEmpty ? '—' : block,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 与多行地址首行对齐的轻量按钮（避免 [IconButton] 默认高度把图标垂直居中到整块中间）。
  Widget _topAlignedIconButton({
    required BuildContext context,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    final c = onPressed == null ? color.withValues(alpha: 0.35) : color;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 20, color: c),
        ),
      ),
    );
  }
}
