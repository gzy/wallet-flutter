import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/wallet_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/pin_keypad.dart';

/// 已设置 PIN 且会话未解锁时全屏展示
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final ValueNotifier<String> _pin = ValueNotifier<String>('');
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submitIfComplete() async {
    if (_pin.value.length != 6 || _busy) return;
    setState(() => _busy = true);
    final entered = _pin.value;
    if (!mounted) return;
    final r = await context.read<WalletController>().unlockSession(entered);
    if (!mounted) return;
    if (!r.ok) {
      final msg = r.lockedSeconds != null && r.lockedSeconds! > 0
          ? 'PIN 已锁定，请 ${r.lockedSeconds}s 后再试'
          : (r.remainingAttempts != null ? 'PIN 不正确，还可尝试 ${r.remainingAttempts} 次' : 'PIN 不正确');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      _pin.value = '';
      setState(() => _busy = false);
      return;
    }
    _pin.value = '';
    if (mounted) setState(() => _busy = false);
  }

  void _onDigit(String n) {
    if (_busy || _pin.value.length >= 6) return;
    _pin.value = _pin.value + n;
    if (_pin.value.length == 6) {
      unawaited(_submitIfComplete());
    }
  }

  void _delete() {
    if (_busy || _pin.value.isEmpty) return;
    _pin.value = _pin.value.substring(0, _pin.value.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 36),
            const Text(
              '欢迎回来！',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '使用密码解锁我的加密钱包',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
                height: 1.35,
              ),
            ),
            const Spacer(flex: 2),
            ValueListenableBuilder<String>(
              valueListenable: _pin,
              builder: (_, pin, __) => PinDotsRow(length: pin.length),
            ),
            const Spacer(flex: 3),
            PinNumericKeypad(
              enabled: !_busy,
              onDigit: _onDigit,
              onBackspace: _delete,
            ),
            SizedBox(height: MediaQuery.paddingOf(context).bottom + 8),
          ],
        ),
      ),
    );
  }
}
