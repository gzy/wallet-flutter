import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 静态 SVG 映射；新增币种时从何处取资源见 docs/assets-icon-sources.md。
class CoinIcon extends StatelessWidget {
  final String symbol;
  final double size;

  const CoinIcon({
    super.key,
    required this.symbol,
    this.size = 34,
  });

  static const Map<String, String> _assetBySymbol = {
    'BTC': 'assets/coins/btc.svg',
    'ETH': 'assets/coins/eth.svg',
    'BNB': 'assets/coins/bnb.svg',
    'SOL': 'assets/coins/sol.svg',
    'USDT': 'assets/coins/usdt.svg',
    'USDC': 'assets/coins/usdc.svg',
    'TRX': 'assets/coins/trx.svg',
    'XRP': 'assets/coins/xrp.svg',
    // Polygon 目前后端返回 symbol=POL，但多数图标库仍用 MATIC 命名
    'POL': 'assets/coins/matic.svg',
  };

  @override
  Widget build(BuildContext context) {
    final sym = symbol.trim().toUpperCase();
    final asset = _assetBySymbol[sym];
    if (asset != null) {
      return SvgPicture.asset(
        asset,
        width: size,
        height: size,
      );
    }
    final letter = sym.isEmpty ? '?' : sym.substring(0, 1);
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFF1C1F24),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.5,
          height: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

