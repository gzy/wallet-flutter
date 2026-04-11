import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// SafePal 风格 PIN 屏配色（略浅于纯黑底，键盘区与按键分层）
class PinKeypadColors {
  PinKeypadColors._();

  static const Color keypadTray = Color(0xFF141416);
  static const Color keyBackground = Color(0xFF2C2C2E);
  static const Color pinBoxBorder = Color(0xFF5C5C62);
  static const Color pinBoxBorderActive = Color(0xFF8E8E93);
}

/// 仅随 [length] 重建，用于配合 [ValueListenableBuilder]。
class PinDotsRow extends StatelessWidget {
  const PinDotsRow({
    super.key,
    required this.length,
    this.size = 46,
    this.gap = 10,
  });

  final int length;
  final double size;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) {
        final filled = i < length;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: gap / 2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            width: size,
            height: size,
            decoration: BoxDecoration(
              border: Border.all(
                color: filled ? PinKeypadColors.pinBoxBorderActive : PinKeypadColors.pinBoxBorder,
                width: 1,
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
          ),
        );
      }),
    );
  }
}

/// 自定义数字键盘：无 PIN 状态，不因每一位输入而整表重建。
class PinNumericKeypad extends StatelessWidget {
  const PinNumericKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.enabled = true,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool enabled;

  static const double _rowGap = 12;
  static const double _keyHeight = 52;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth;
        const hPad = 20.0;
        const between = 10.0;
        final keyW = (maxW - hPad * 2 - between * 2) / 3;

        Widget key(String label) => _PinKey(
              label: label,
              width: keyW,
              height: _keyHeight,
              enabled: enabled,
              onTap: () {
                HapticFeedback.selectionClick();
                onDigit(label);
              },
            );

        return RepaintBoundary(
          child: ColoredBox(
            color: PinKeypadColors.keypadTray,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(hPad, 20, hPad, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [key('1'), key('2'), key('3')],
                  ),
                  const SizedBox(height: _rowGap),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [key('4'), key('5'), key('6')],
                  ),
                  const SizedBox(height: _rowGap),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [key('7'), key('8'), key('9')],
                  ),
                  const SizedBox(height: _rowGap),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      SizedBox(width: keyW, height: _keyHeight),
                      key('0'),
                      _PinBackspace(
                        width: keyW,
                        height: _keyHeight,
                        enabled: enabled,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onBackspace();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PinKey extends StatefulWidget {
  const _PinKey({
    required this.label,
    required this.width,
    required this.height,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final double width;
  final double height;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_PinKey> createState() => _PinKeyState();
}

class _PinKeyState extends State<_PinKey> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (!widget.enabled) return;
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && _pressed;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) {
        _setPressed(false);
        if (widget.enabled) widget.onTap();
      },
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: active ? 0.96 : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          width: widget.width,
          height: widget.height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? PinKeypadColors.keyBackground.withValues(alpha: 0.88)
                : PinKeypadColors.keyBackground,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.enabled ? AppColors.textPrimary : AppColors.textMuted,
              fontSize: 24,
              fontWeight: FontWeight.w500,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _PinBackspace extends StatefulWidget {
  const _PinBackspace({
    required this.width,
    required this.height,
    required this.enabled,
    required this.onTap,
  });

  final double width;
  final double height;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_PinBackspace> createState() => _PinBackspaceState();
}

class _PinBackspaceState extends State<_PinBackspace> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && _pressed;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = widget.enabled),
      onTapUp: (_) {
        setState(() => _pressed = false);
        if (widget.enabled) widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: active ? 0.96 : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          width: widget.width,
          height: widget.height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? PinKeypadColors.keyBackground.withValues(alpha: 0.88)
                : PinKeypadColors.keyBackground,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.backspace_outlined,
            color: widget.enabled ? AppColors.textPrimary : AppColors.textMuted,
            size: 22,
          ),
        ),
      ),
    );
  }
}
