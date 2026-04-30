import 'package:flutter/material.dart';

import 'dart:async' show unawaited;

import '../services/wallet/secure_storage_service.dart';
import '../theme/app_colors.dart';
import 'pin_keypad.dart';

/// 底部弹出的 6 位 PIN 校验（与转账授权等共用交互）。
class PinVerifySheet extends StatefulWidget {
  const PinVerifySheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.verify,
  });

  final String title;
  final String subtitle;
  final Future<PinVerifyResult> Function(String pin) verify;

  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Future<PinVerifyResult> Function(String pin) verify,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) =>
          PinVerifySheet(title: title, subtitle: subtitle, verify: verify),
    );
  }

  @override
  State<PinVerifySheet> createState() => _PinVerifySheetState();
}

class _PinVerifySheetState extends State<PinVerifySheet> {
  // 注意：历史版本这里用过 String `_pin`。为避免热重载残留导致类型不一致崩溃，这里改名为 `_pinVN`。
  final ValueNotifier<String> _pinVN = ValueNotifier<String>('');
  bool _busy = false;

  void _onDigit(String n) {
    if (_busy || _pinVN.value.length >= 6) return;
    _pinVN.value = _pinVN.value + n;
    if (_pinVN.value.length == 6) {
      unawaited(_submitIfComplete());
    }
  }

  Future<void> _submitIfComplete() async {
    if (_busy || _pinVN.value.length != 6) return;
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    final r = await widget.verify(_pinVN.value);
    if (!mounted) return;
    if (!r.ok) {
      final msg = r.lockedSeconds != null && r.lockedSeconds! > 0
          ? 'PIN 已锁定，请 ${r.lockedSeconds}s 后再试'
          : (r.remainingAttempts != null
              ? 'PIN 不正确，还可尝试 ${r.remainingAttempts} 次'
              : 'PIN 不正确');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      _pinVN.value = '';
      setState(() => _busy = false);
      return;
    }
    Navigator.of(context).pop(true);
  }

  void _delete() {
    if (_pinVN.value.isEmpty || _busy) return;
    _pinVN.value = _pinVN.value.substring(0, _pinVN.value.length - 1);
  }

  @override
  void dispose() {
    _pinVN.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Spacer(),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon:
                        const Icon(Icons.close, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                widget.subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<String>(
                valueListenable: _pinVN,
                builder: (_, pin, __) =>
                    PinDotsRow(length: pin.length, size: 44, gap: 12),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: PinNumericKeypad(
                  enabled: !_busy,
                  onDigit: _onDigit,
                  onBackspace: _delete,
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}
