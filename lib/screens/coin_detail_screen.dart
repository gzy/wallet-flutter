import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/coin_data.dart';
import '../providers/wallet_controller.dart';
import '../theme/app_colors.dart';
import 'flash_screen.dart';
import 'receive_screen.dart';
import 'transfer_screen.dart';

String _walletAddressSubtitle(WalletController wc) {
  final name = wc.activeWallet?.name;
  final hex = wc.addressHex;
  if (hex == null || hex.length < 10) {
    return name ?? '未连接钱包';
  }
  final short = '${hex.substring(0, 6)}…${hex.substring(hex.length - 4)}';
  if (name != null && name.isNotEmpty) {
    return '$name  $short';
  }
  return short;
}

class CoinDetailScreen extends StatelessWidget {
  final CoinData coin;
  const CoinDetailScreen({super.key, required this.coin});

  @override
  Widget build(BuildContext context) {
    final wc = context.watch<WalletController>();
    final subtitle = _walletAddressSubtitle(wc);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: Text(coin.symbol,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        actions: const [
          Icon(Icons.tune, color: AppColors.textPrimary, size: 22),
          SizedBox(width: 12),
          Icon(Icons.more_vert, color: AppColors.textPrimary, size: 22),
          SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 11,
                  backgroundColor: Color(0xFF2C2F37),
                  child: Icon(Icons.description_outlined,
                      size: 14, color: AppColors.textSecondary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    subtitle,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.copy, size: 13, color: AppColors.textMuted),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _tokenAvatar(coin),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayBalance(coin.balance),
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: _balanceFontSize(coin.balance),
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    coin.price == 0
                        ? Text(
                            '\$${coin.balanceUSD.toStringAsFixed(coin.balanceUSD == 0 ? 0 : 4)} | 未接入行情',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 14),
                          )
                        : RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                  color: AppColors.textSecondary, fontSize: 14),
                              children: [
                                TextSpan(
                                  text:
                                      '\$${coin.balanceUSD.toStringAsFixed(coin.balanceUSD == 0 ? 0 : 4)} | \$${coin.price.toStringAsFixed(2)}  ',
                                ),
                                TextSpan(
                                  text:
                                      '${coin.priceChange24h >= 0 ? '+' : ''}${coin.priceChange24h.toStringAsFixed(2)}%',
                                  style: TextStyle(
                                    color: coin.priceChange24h < 0
                                        ? AppColors.error
                                        : const Color(0xFF10E8CF),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 13),
            Row(
              children: [
                Expanded(
                  child: _quick(context, Icons.north_east, '闪兑', () {
                    Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const FlashScreen()));
                  }),
                ),
                Expanded(
                  child:
                      _quick(context, Icons.local_gas_station, '买Gas', () {}),
                ),
                Expanded(
                  child: _quick(context, Icons.person_outline, '授权', () {}),
                ),
                Expanded(
                  child:
                      _quick(context, Icons.inventory_2_outlined, '浏览器', () {}),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child:
                      _quick(context, Icons.travel_explore, 'CoinGecko', () {}),
                ),
                Expanded(
                  child: _quick(
                      context, Icons.hexagon_outlined, 'SoSoValue', () {}),
                ),
                const Expanded(child: SizedBox()),
                const Expanded(child: SizedBox()),
              ],
            ),
            const SizedBox(height: 15),
            const Row(
              children: [
                Text('交易',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                SizedBox(width: 16),
                Text('资讯',
                    style: TextStyle(
                        fontSize: 18, color: AppColors.textSecondary)),
              ],
            ),
            const SizedBox(height: 4),
            const Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 34,
                child: Divider(thickness: 3, color: AppColors.accent),
              ),
            ),
            const SizedBox(height: 7),
            const SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _TagChip(label: '全部', selected: true),
                  _TagChip(label: '收款'),
                  _TagChip(label: '转账'),
                  _TagChip(label: '待确认'),
                  _TagChip(label: '矿工费'),
                  _TagChip(label: '⚙'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.description_outlined,
                        size: 86, color: AppColors.textMuted.withOpacity(0.9)),
                    const SizedBox(height: 8),
                    const Text('暂无记录',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 18)),
                    const SizedBox(height: 18),
                    const Text(
                      '在区块浏览器中查看 >',
                      style: TextStyle(color: AppColors.accent, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const ReceiveScreen()),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: Color(0xFF3A3F54), width: 1.2),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text(
                        '收款',
                        style: TextStyle(
                          fontSize: 18,
                          color: Color(0xFFE7EBFF),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [AppColors.accentStart, AppColors.accentEnd],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const TransferScreen()),
                            );
                          },
                          child: const Center(
                            child: Text(
                              '转账',
                              style: TextStyle(
                                fontSize: 18,
                                color: AppColors.accentText,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _quick(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.textPrimary, size: 22),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _tokenAvatar(CoinData coin) {
    final symbol = coin.symbol.toUpperCase();
    if (symbol == 'BNB') {
      return Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(
          color: Color(0xFFF0B90B),
          shape: BoxShape.circle,
        ),
        child: const Stack(
          alignment: Alignment.center,
          children: [
            Positioned(top: 12, child: _Diamond(size: 5)),
            Positioned(bottom: 14, child: _Diamond(size: 5)),
            Positioned(left: 12, child: _Diamond(size: 5)),
            Positioned(right: 12, child: _Diamond(size: 5)),
            Positioned(top: 23, child: _Diamond(size: 8)),
          ],
        ),
      );
    }

    if (symbol == 'ETH') {
      return Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(
          color: Color(0xFF6B7280),
          shape: BoxShape.circle,
        ),
        child: const Center(child: _Diamond(size: 12)),
      );
    }

    if (symbol == 'BTC') {
      return const CircleAvatar(
        radius: 28,
        backgroundColor: Color(0xFFF7931A),
        child: Text('₿',
            style: TextStyle(
                fontSize: 24,
                color: Colors.white,
                fontWeight: FontWeight.w700)),
      );
    }

    return CircleAvatar(
      radius: 28,
      backgroundColor: const Color(0xFF4B5563),
      child: Text(
        symbol.substring(0, 1),
        style: const TextStyle(
            fontSize: 22, color: Colors.white, fontWeight: FontWeight.w700),
      ),
    );
  }

  String _displayBalance(double value) {
    if (value == 0) return '0';
    if (value >= 1)
      return value
          .toStringAsFixed(4)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    return value
        .toStringAsFixed(6)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  double _balanceFontSize(double value) {
    final text = _displayBalance(value);
    if (text.length <= 1) return 52;
    if (text.length <= 4) return 50;
    if (text.length <= 6) return 44;
    return 40;
  }
}

class _Diamond extends StatelessWidget {
  final double size;
  const _Diamond({required this.size});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.785398, // 45°
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(1.2)),
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final bool selected;
  const _TagChip({required this.label, this.selected = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? AppColors.accent : Colors.transparent,
        border: Border.all(
            color: selected ? AppColors.accent : AppColors.borderSoft),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontSize: 14),
      ),
    );
  }
}
