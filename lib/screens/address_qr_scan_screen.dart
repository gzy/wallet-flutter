import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

/// 从二维码内容中尽量提取链上收款地址（支持常见 URI 前缀）。
String normalizeAddressFromQrPayload(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return s;
  final oneLine = s.replaceAll(RegExp(r'[\s\n\r]+'), '');
  final lower = oneLine.toLowerCase();
  if (lower.startsWith('ethereum:')) {
    final m = RegExp(
      r'^ethereum:(0x[a-fA-F0-9]{40})',
      caseSensitive: false,
    ).firstMatch(oneLine);
    if (m != null) return m.group(1)!;
  }
  if (lower.startsWith('tron:')) {
    final m = RegExp(
      r'^tron:(T[a-zA-Z0-9]{33})',
      caseSensitive: false,
    ).firstMatch(oneLine);
    if (m != null) return m.group(1)!;
  }
  return s.trim();
}

/// 全屏相机扫码，成功时 `Navigator.pop(context, String)`，取消为 `null`。
class AddressQrScanScreen extends StatefulWidget {
  const AddressQrScanScreen({super.key});

  @override
  State<AddressQrScanScreen> createState() => _AddressQrScanScreenState();
}

class _AddressQrScanScreenState extends State<AddressQrScanScreen> {
  bool _handled = false;

  void _onScan(Code code) {
    if (_handled) return;
    final t = code.text;
    if (t == null || t.trim().isEmpty) return;
    _handled = true;
    if (!mounted) return;
    Navigator.of(context).pop<String>(normalizeAddressFromQrPayload(t));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('扫描收款地址'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 库默认 cropPercent=0.5 只扫画面中心一半，码稍偏就失败；改为 1.0 全画面。
          // scanDelay 默认 1000ms 导致识别失败后很久才再试，体感「卡顿」。
          ReaderWidget(
            onScan: _onScan,
            codeFormat: Format.qrCode | Format.microQRCode,
            maxNumberOfSymbols: 1,
            cropPercent: 1.0,
            tryHarder: true,
            tryRotate: true,
            tryInverted: true,
            tryDownscale: true,
            resolution: ResolutionPreset.high,
            showToggleCamera: false,
            showGallery: true,
            scanDelay: const Duration(milliseconds: 90),
            scanDelaySuccess: const Duration(milliseconds: 200),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 100,
            child: IgnorePointer(
              child: Text(
                '对准二维码，保持稳定与光线；可稍远一点避免模糊',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
