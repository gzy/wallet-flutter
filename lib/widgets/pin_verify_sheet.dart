import 'package:flutter/material.dart';

import '../services/wallet/secure_storage_service.dart';
import '../theme/app_colors.dart';

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
      builder: (_) => PinVerifySheet(title: title, subtitle: subtitle, verify: verify),
    );
  }

  @override
  State<PinVerifySheet> createState() => _PinVerifySheetState();
}

class _PinVerifySheetState extends State<PinVerifySheet> {
  String _pin = '';
  bool _busy = false;

  Future<void> _tap(String n) async {
    if (_pin.length >= 6 || _busy) return;
    setState(() => _pin = '$_pin$n');
    if (_pin.length != 6) return;

    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    final r = await widget.verify(_pin);
    if (!mounted) return;
    if (!r.ok) {
      final msg = r.lockedSeconds != null && r.lockedSeconds! > 0
          ? 'PIN 已锁定，请 ${r.lockedSeconds}s 后再试'
          : (r.remainingAttempts != null
              ? 'PIN 不正确，还可尝试 ${r.remainingAttempts} 次'
              : 'PIN 不正确');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      setState(() {
        _pin = '';
        _busy = false;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  void _delete() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
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
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                widget.subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (i) {
                  final filled = i < _pin.length;
                  return Container(
                    width: 44,
                    height: 44,
                    margin: const EdgeInsets.symmetric(horizontal: 7),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: filled ? AppColors.textPrimary : AppColors.borderSoft,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: filled
                        ? Center(
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: AppColors.textPrimary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                        : null,
                  );
                }),
              ),
              const SizedBox(height: 18),
              _KeyRow(keys: const ['1', '2', '3'], onTap: _tap),
              const SizedBox(height: 10),
              _KeyRow(keys: const ['4', '5', '6'], onTap: _tap),
              const SizedBox(height: 10),
              _KeyRow(keys: const ['7', '8', '9'], onTap: _tap),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 88, height: 54),
                  _KeyButton(label: '0', onTap: () => _tap('0')),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 88,
                    height: 54,
                    child: TextButton(
                      onPressed: _delete,
                      child: const Icon(Icons.backspace_outlined, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.keys, required this.onTap});

  final List<String> keys;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final k in keys) ...[
          _KeyButton(label: k, onTap: () => onTap(k)),
          if (k != keys.last) const SizedBox(width: 12),
        ],
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 88,
        height: 54,
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
