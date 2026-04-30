import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/wallet_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/coin_icon.dart';

class FlashScreen extends StatefulWidget {
  const FlashScreen({super.key});

  @override
  State<FlashScreen> createState() => _FlashScreenState();
}

class _FlashScreenState extends State<FlashScreen> {
  static const List<(String, String)> _tokens = [
    ('ETH', 'Arbitrum One'),
    ('BNB', 'BEP20'),
    ('BTC', 'Bitcoin'),
  ];

  (String, String) _from = _tokens[0];
  (String, String) _to = _tokens[1];
  String _rateType = 'floating';
  final TextEditingController _fromAmountController = TextEditingController();

  @override
  void dispose() {
    _fromAmountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<WalletController>();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            children: [
              _header(),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerRight,
                child: Icon(Icons.history,
                    color: AppColors.textSecondary, size: 22),
              ),
              const SizedBox(height: 10),
              _swapPanel(),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {},
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.surfaceElevated,
                    foregroundColor: AppColors.textPrimary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('闪兑', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _providerCard(),
              const SizedBox(height: 14),
              TextButton(
                onPressed: () {},
                child: const Text('展示更多⌄',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.borderSoft),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        color: AppColors.textSecondary, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '请注意，由于汇率波动，你收到的金额和预估金额可能会存在少许差异。',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final title = context.read<WalletController>().activeWallet?.name ?? '闪兑';
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.chevron_left, color: AppColors.textPrimary),
        ),
        Expanded(
          child: Center(
            child: Text(title, style: const TextStyle(fontSize: 16)),
          ),
        ),
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderSoft),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            children: [
              Icon(Icons.more_horiz, size: 18, color: AppColors.textSecondary),
              SizedBox(width: 8),
              SizedBox(
                  height: 16,
                  child: VerticalDivider(color: AppColors.borderSoft)),
              SizedBox(width: 8),
              Icon(Icons.horizontal_rule,
                  size: 18, color: AppColors.textSecondary),
              SizedBox(width: 8),
              SizedBox(
                  height: 16,
                  child: VerticalDivider(color: AppColors.borderSoft)),
              SizedBox(width: 8),
              Icon(Icons.close, size: 16, color: AppColors.textSecondary),
            ],
          ),
        ),
      ],
    );
  }

  Widget _swapPanel() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFF191C22),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _swapSection(
                title: '支付',
                token: _from,
                balanceText: '0',
                amountWidget: SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _fromAmountController,
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      hintText: '输入金额',
                      hintStyle: TextStyle(color: AppColors.textMuted),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                onPick: () async {
                  final picked = await _openTokenPicker();
                  if (picked != null) setState(() => _from = picked);
                },
              ),
              const SizedBox(height: 14),
              const Divider(color: AppColors.border),
              const SizedBox(height: 14),
              _swapSection(
                title: '得到',
                token: _to,
                balanceText: '0',
                amountWidget: const Text(
                  '0',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 30),
                ),
                onPick: () async {
                  final picked = await _openTokenPicker();
                  if (picked != null) setState(() => _to = picked);
                },
              ),
              const SizedBox(height: 14),
              const Divider(color: AppColors.border),
              const SizedBox(height: 10),
              Row(
                children: [
                  _rateItem('floating', '浮动汇率'),
                  const SizedBox(width: 16),
                  _rateItem('fixed', '固定汇率'),
                  const SizedBox(width: 8),
                  const Icon(Icons.help_outline,
                      color: AppColors.textSecondary, size: 18),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          top: 132,
          child: InkWell(
            onTap: () => setState(() {
              final old = _from;
              _from = _to;
              _to = old;
            }),
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Color(0xFF2A2E36),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.swap_vert, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _swapSection({
    required String title,
    required (String, String) token,
    required String balanceText,
    required Widget amountWidget,
    required VoidCallback onPick,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Text(title, style: const TextStyle(fontSize: 16)),
            const Spacer(),
            const Icon(Icons.account_balance_wallet_outlined,
                size: 15, color: AppColors.textMuted),
            const SizedBox(width: 4),
            Text(balanceText,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(width: 4),
            const Text('最大', style: TextStyle(color: AppColors.accent)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            InkWell(
              onTap: onPick,
              child: Row(
                children: [
                  CoinIcon(symbol: token.$1, size: 40),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(token.$1,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600)),
                      Text(token.$2,
                          style: const TextStyle(
                              fontSize: 14, color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.keyboard_arrow_down,
                      color: AppColors.textMuted, size: 18),
                ],
              ),
            ),
            const Spacer(),
            amountWidget,
          ],
        ),
      ],
    );
  }

  Widget _rateItem(String value, String label) {
    final active = _rateType == value;
    return InkWell(
      onTap: () => setState(() => _rateType = value),
      child: Row(
        children: [
          Icon(
            active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            color: active ? AppColors.accent : AppColors.textMuted,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 15)),
        ],
      ),
    );
  }

  Widget _providerCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        children: [
          Row(
            children: [
              Text('服务商', style: TextStyle(color: AppColors.textSecondary)),
              Spacer(),
              Text('🚀 Changelly', style: TextStyle(fontSize: 16)),
              SizedBox(width: 4),
              Icon(Icons.chevron_right,
                  color: AppColors.textSecondary, size: 18),
            ],
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Text('滑点', style: TextStyle(color: AppColors.textSecondary)),
              Spacer(),
              Text('3%', style: TextStyle(fontSize: 16)),
              SizedBox(width: 4),
              Icon(Icons.chevron_right,
                  color: AppColors.textSecondary, size: 18),
            ],
          ),
        ],
      ),
    );
  }

  Future<(String, String)?> _openTokenPicker() async {
    return showModalBottomSheet<(String, String)>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const Text(
                '选择币种',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              ..._tokens.map(
                (item) => ListTile(
                  onTap: () => Navigator.pop(context, item),
                  title: Text(
                    '${item.$1} (${item.$2})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
