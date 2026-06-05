import 'package:flutter/material.dart';

/// 某一后台模式模块的悬浮窗展示配置。
class BackendFloatConfig {
  const BackendFloatConfig({
    required this.moduleId,
    required this.stripTitle,
    required this.icon,
    this.iconBackground = const Color(0xFF22C55E),
    this.showCircleBadge = true,
    this.aboutTitle = '关于',
    this.aboutBody,
    this.favoriteEnabled = true,
  });

  /// 模块标识，便于持久化/埋点扩展。
  final String moduleId;
  final String stripTitle;
  final IconData icon;
  final Color iconBackground;
  final bool showCircleBadge;
  final String aboutTitle;
  final String? aboutBody;
  final bool favoriteEnabled;
}
