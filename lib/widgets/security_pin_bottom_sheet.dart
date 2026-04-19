import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 底部 6 位数字安全密码。
///
/// - [setupMode]==true 且为首次：先「设置安全密码」，再「再次确认密码」，两次一致后才 [onSubmit]。
/// - [setupMode]==false：单次输入「请输入安全密码」后 [onSubmit]（已设过 PIN 时的校验场景）。
class SecurityPinBottomSheet extends StatefulWidget {
  const SecurityPinBottomSheet({
    super.key,
    required this.setupMode,
    required this.onSubmit,
  });

  final bool setupMode;
  final Future<void> Function(String pin) onSubmit;

  @override
  State<SecurityPinBottomSheet> createState() => _SecurityPinBottomSheetState();
}

class _SecurityPinBottomSheetState extends State<SecurityPinBottomSheet> {
  String _pin = '';
  bool _busy = false;

  /// 首次设置时：第一轮 6 位填完后暂存于此，再输入第二轮。
  String? _firstPin;

  String get _title {
    if (!widget.setupMode) return '请输入安全密码';
    if (_firstPin == null) return '设置安全密码';
    return '再次确认密码';
  }

  Future<void> _tap(String n) async {
    if (_pin.length >= 6 || _busy) return;
    setState(() => _pin = '$_pin$n');
    if (_pin.length != 6) return;

    if (!widget.setupMode) {
      await _submitCurrent();
      return;
    }
    if (_firstPin == null) {
      setState(() {
        _firstPin = _pin;
        _pin = '';
      });
      return;
    }
    if (_pin != _firstPin) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('两次输入不一致，请重新设置')),
      );
      setState(() {
        _firstPin = null;
        _pin = '';
      });
      return;
    }
    await _submitCurrent();
  }

  Future<void> _submitCurrent() async {
    final pin = _pin;
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    try {
      await widget.onSubmit(pin);
    } catch (_) {
      if (mounted) {
        setState(() {
          _pin = '';
          _busy = false;
          if (widget.setupMode) {
            _firstPin = null;
          }
        });
      }
      rethrow;
    }
    if (mounted) {
      setState(() => _busy = false);
    }
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
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(child: SizedBox.shrink()),
                  Text(
                    _title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.setupMode && _firstPin == null) ...[
                const SizedBox(height: 6),
                const Text(
                  '用于解锁应用与授权操作',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Row(
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
                        color: filled ? AppColors.textPrimary : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: filled
                          ? Center(
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Colors.black,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            )
                          : null,
                    );
                  }),
                ),
              ),
              _KeyRow(keys: const ['1', '2', '3'], onTap: (k) => _tap(k)),
              const SizedBox(height: 10),
              _KeyRow(keys: const ['4', '5', '6'], onTap: (k) => _tap(k)),
              const SizedBox(height: 10),
              _KeyRow(keys: const ['7', '8', '9'], onTap: (k) => _tap(k)),
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
        ]
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
