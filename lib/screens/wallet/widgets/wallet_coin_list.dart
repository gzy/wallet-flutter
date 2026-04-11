import 'package:flutter/material.dart';
import 'package:wallet_flutter/screens/coin_detail_screen.dart';
import '../../../models/coin_data.dart';
import '../../../theme/app_colors.dart';

class WalletCoinList extends StatelessWidget {
  final List<CoinData> coins;

  const WalletCoinList({super.key, required this.coins});

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final coin = coins[index];
            return InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => CoinDetailScreen(coin: coin)),
                );
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Text(coin.icon, style: const TextStyle(fontSize: 34), textAlign: TextAlign.center),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                coin.symbol,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (coin.network != null) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '(${coin.network})',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          coin.price == 0
                              ? const Text(
                                  '未接入行情',
                                  style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                                )
                              : Row(
                                  children: [
                                    Text(
                                      '\$${coin.price.toStringAsFixed(2)}',
                                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${coin.priceChange24h.toStringAsFixed(2)}%',
                                      style: TextStyle(
                                        color: coin.priceChange24h < 0
                                            ? AppColors.error
                                            : coin.priceChange24h > 0
                                                ? const Color(0xFF4ADE80)
                                                : AppColors.textSecondary,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          coin.balance.toString(),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '\$${coin.balanceUSD.toStringAsFixed(coin.balanceUSD == 0 ? 0 : 4)}',
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
          childCount: coins.length,
        ),
      ),
    );
  }
}
