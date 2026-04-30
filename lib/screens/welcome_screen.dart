import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'add_wallet_screen.dart';
import 'import_wallet_screen.dart';

/// 设计：交付稿欢迎页。首帧仅背景 + Logo，再出现底部双按钮。
///
/// 字体：设计稿为 Alibaba PuHuiTi 3.0；未内置字体文件时由系统回退，将 `.ttf` 加入 `pubspec.yaml` 的 `fonts` 后即可生效。
class WelcomeScreen extends StatefulWidget {
  final bool allowActions;
  const WelcomeScreen({super.key, this.allowActions = true});

  /// 与 Figma 一致的 family 名；注册字体后生效。
  static const String buttonFontFamily = 'Alibaba PuHuiTi 3.0';

  static const Color _primaryGradientStart = Color(0xFF6E9BFC);
  static const Color _primaryGradientEnd = Color(0xFFA246EF);
  static Color get _secondaryFill =>
      const Color(0xFF111116).withValues(alpha: 0.40);

  static TextStyle get buttonTextStyle => const TextStyle(
        fontFamily: buttonFontFamily,
        color: Color(0xFFFFFFFF),
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 1.0,
      );

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  static const _revealDelay = Duration(seconds: 2);
  bool _showActions = false;
  Timer? _revealTimer;
  String? _versionLabel;

  @override
  void initState() {
    super.initState();
    unawaited(_loadVersionLabel());
    if (widget.allowActions) {
      _revealTimer = Timer(_revealDelay, () {
        if (!mounted) return;
        setState(() => _showActions = true);
      });
    }
  }

  Future<void> _loadVersionLabel() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final v = info.version.trim();
      final b = info.buildNumber.trim();
      if (!mounted) return;
      setState(() => _versionLabel = b.isEmpty ? 'v$v' : 'v$v ($b)');
    } catch (_) {
      // ignore: best-effort UI
    }
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: const Color(0xFF0A1628),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF050A18),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/welcome/welcome_gradient.png'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Center(
              child: ColorFiltered(
                colorFilter: const ColorFilter.mode(
                  Color(0xFFFFFFFF),
                  BlendMode.srcATop,
                ),
                child: Image.asset(
                  'assets/icon/app_icon.png',
                  width: 88,
                  height: 88,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            if (_versionLabel != null)
              Positioned(
                left: 24,
                right: 24,
                bottom: 24 + bottomInset + (_showActions ? 116 : 0),
                child: Text(
                  _versionLabel!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFB8BCC5),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            if (widget.allowActions)
              Positioned(
                left: 24,
                right: 24,
                bottom: 24 + bottomInset,
                child: AnimatedOpacity(
                  opacity: _showActions ? 1 : 0,
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  child: IgnorePointer(
                    ignoring: !_showActions,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _WelcomePrimaryButton(
                          label: 'Create Wallet',
                          onPressed: () {
                            Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => const AddWalletScreen(
                                  openCreateDialogOnOpen: true,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        _WelcomeSecondaryButton(
                          label: 'Import Wallet',
                          onPressed: () {
                            Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => const ImportWalletScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WelcomePrimaryButton extends StatelessWidget {
  const _WelcomePrimaryButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                WelcomeScreen._primaryGradientStart,
                WelcomeScreen._primaryGradientEnd,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: WelcomeScreen.buttonTextStyle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeSecondaryButton extends StatelessWidget {
  const _WelcomeSecondaryButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: WelcomeScreen._secondaryFill,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: WelcomeScreen.buttonTextStyle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
