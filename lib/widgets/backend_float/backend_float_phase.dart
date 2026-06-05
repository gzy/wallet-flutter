/// 后台模式悬浮窗阶段（通用，与具体业务模块无关）。
enum BackendFloatPhase {
  hidden,
  /// 可拖动小圆
  edge,
  /// 悬浮长条（展示时有遮罩）
  capsule,
  /// 全屏业务页
  expanded,
}
