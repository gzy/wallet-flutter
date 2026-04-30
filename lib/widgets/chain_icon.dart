import 'package:flutter/material.dart';

class ChainIcon extends StatelessWidget {
  final String chainCode;
  final double size;

  const ChainIcon({
    super.key,
    required this.chainCode,
    this.size = 42,
  });

  static const Map<String, String> _assetByChainCode = {
    'ARB': 'assets/chains/arb.png',
    'BSC': 'assets/chains/bsc.png',
    'ETH': 'assets/chains/eth.png',
    'POL': 'assets/chains/polygon.png',
    'SOL': 'assets/chains/sol.png',
    'TRX': 'assets/chains/trx.png',
    'XRP': 'assets/chains/xrp.png',
  };

  @override
  Widget build(BuildContext context) {
    final code = chainCode.trim().toUpperCase();
    final asset = _assetByChainCode[code];
    if (asset == null) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0xFF3A3D45),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          code.isEmpty ? '—' : code.substring(0, 1),
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.45,
            height: 1,
          ),
        ),
      );
    }
    return ClipOval(
      child: Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}
