import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Offset;

import '../../services/backend_float/backend_float_settings_store.dart';
import 'backend_float_phase.dart';

/// 后台模式悬浮窗状态机（小圆 → 长条+遮罩 → 全屏）。
///
/// [floatEnabled] 为模块级设置，经 [BackendFloatSettingsStore] 持久化。
class BackendFloatController extends ChangeNotifier {
  BackendFloatController({
    required this.moduleId,
    BackendFloatSettingsStore? settingsStore,
  }) : _settingsStore = settingsStore;

  final String moduleId;
  final BackendFloatSettingsStore? _settingsStore;

  BackendFloatPhase _phase = BackendFloatPhase.hidden;
  bool _floatDisabled = false;
  Offset? _floatAnchor;
  bool _settingsLoaded = false;

  BackendFloatPhase get phase => _phase;
  bool get floatEnabled => !_floatDisabled;
  bool get floatDisabled => _floatDisabled;
  bool get settingsLoaded => _settingsLoaded;
  bool get isVisible => _phase != BackendFloatPhase.hidden;
  Offset? get floatAnchor => _floatAnchor;

  bool get isInFloatWindow =>
      _phase == BackendFloatPhase.edge || _phase == BackendFloatPhase.capsule;

  /// 从本地缓存恢复该模块是否启用浮窗。
  Future<void> loadSettings() async {
    final enabled = await _settingsStore?.readEnabled(moduleId);
    if (enabled != null) {
      _floatDisabled = !enabled;
    }
    _settingsLoaded = true;
    notifyListeners();
  }

  /// 设置并持久化「本模块是否启用浮窗」。
  Future<void> setFloatEnabled(bool enabled) async {
    _floatDisabled = !enabled;
    await _settingsStore?.writeEnabled(moduleId, enabled);
    if (!enabled) {
      _phase = BackendFloatPhase.hidden;
    } else if (_phase == BackendFloatPhase.expanded) {
      _phase = BackendFloatPhase.edge;
    } else if (_phase == BackendFloatPhase.hidden) {
      _phase = BackendFloatPhase.edge;
    }
    notifyListeners();
  }

  void showCircle() {
    if (_floatDisabled) return;
    _phase = BackendFloatPhase.edge;
    notifyListeners();
  }

  /// 入口按钮（如功能格）直接进入全屏页；是否显示小圆由 [floatEnabled] 决定。
  void openPanelDirectly() {
    _phase = BackendFloatPhase.expanded;
    notifyListeners();
  }

  void setFloatAnchor(Offset position) {
    _floatAnchor = position;
    notifyListeners();
  }

  void expandToCapsule() {
    if (_floatDisabled) return;
    if (_phase == BackendFloatPhase.edge) {
      _phase = BackendFloatPhase.capsule;
      notifyListeners();
    }
  }

  void expandToPanel() {
    if (_phase == BackendFloatPhase.capsule) {
      _phase = BackendFloatPhase.expanded;
      notifyListeners();
    }
  }

  void collapsePanelToCircle() {
    if (_floatDisabled) {
      close();
      return;
    }
    if (_phase == BackendFloatPhase.expanded) {
      _phase = BackendFloatPhase.edge;
      notifyListeners();
    }
  }

  void collapseCapsuleToCircle() {
    if (_floatDisabled) {
      close();
      return;
    }
    if (_phase == BackendFloatPhase.capsule) {
      _phase = BackendFloatPhase.edge;
      notifyListeners();
    }
  }

  void close() {
    _phase = BackendFloatPhase.hidden;
    notifyListeners();
  }

  /// 「…」菜单：在「浮窗 / 取消浮窗」间切换并写入本地设置。
  Future<void> toggleFloatFromMenu() async {
    await setFloatEnabled(!floatEnabled);
  }
}
