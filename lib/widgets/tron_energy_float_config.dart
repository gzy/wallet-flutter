import 'package:flutter/material.dart';

import 'backend_float/backend_float_config.dart';

/// 波场能量租赁模块的后台模式悬浮窗配置。
const kTronEnergyFloatConfig = BackendFloatConfig(
  moduleId: 'tron_energy_rental',
  stripTitle: 'Tron Energy Rental',
  icon: Icons.bolt,
  iconBackground: Color(0xFF22C55E),
  showCircleBadge: true,
  favoriteEnabled: false,
);
