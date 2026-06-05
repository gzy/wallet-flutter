import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'backend_float_config.dart';
import 'backend_float_controller.dart';
import 'backend_float_phase.dart';

/// 通用后台模式悬浮窗：小圆 → 长条（带遮罩）→ 全屏。
///
/// 新业务模块只需提供 [BackendFloatConfig] 与 [expandedBuilder]。
class BackendFloatOverlay extends StatefulWidget {
  const BackendFloatOverlay({
    super.key,
    required this.controller,
    required this.config,
    required this.expandedBuilder,
  });

  final BackendFloatController controller;
  final BackendFloatConfig config;
  final Widget Function(BuildContext context) expandedBuilder;

  @override
  State<BackendFloatOverlay> createState() => _BackendFloatOverlayState();
}

class _BackendFloatOverlayState extends State<BackendFloatOverlay> {
  static const double _circleSize = 52;
  static const double _capsuleHeight = 56;
  static const double _capsuleMaxWidth = 300;
  static const double _edgePadding = 12;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Offset _defaultAnchor(Size size) {
    return Offset(
      size.width - _circleSize - _edgePadding,
      size.height * 0.52,
    );
  }

  Offset _resolveAnchor(Size size) {
    return _clampAnchor(
      widget.controller.floatAnchor ?? _defaultAnchor(size),
      size,
    );
  }

  Offset _clampAnchor(Offset pos, Size size) {
    final maxX = size.width - _circleSize - _edgePadding;
    final maxY = size.height - _circleSize - 72;
    return Offset(
      pos.dx.clamp(_edgePadding, maxX),
      pos.dy.clamp(80.0, maxY > 80 ? maxY : 80.0),
    );
  }

  ({double left, double top, double width}) _capsuleLayout(Size size) {
    final anchor = _resolveAnchor(size);
    final width = _capsuleMaxWidth.clamp(
      200.0,
      size.width - 2 * _edgePadding,
    );
    var left = anchor.dx;
    if (left + width > size.width - _edgePadding) {
      left = size.width - _edgePadding - width;
    }
    left = left.clamp(_edgePadding, size.width - width - _edgePadding);
    final top = anchor.dy.clamp(
      80.0,
      size.height - _capsuleHeight - 72,
    );
    return (left: left, top: top, width: width);
  }

  @override
  Widget build(BuildContext context) {
    final phase = widget.controller.phase;
    if (phase == BackendFloatPhase.hidden) {
      return const SizedBox.shrink();
    }

    final size = MediaQuery.sizeOf(context);
    final cfg = widget.config;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (phase == BackendFloatPhase.capsule) ...[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.controller.collapseCapsuleToCircle,
              child: Container(color: Colors.black54),
            ),
          ),
          _buildPositionedStrip(size, cfg),
        ],
        if (phase == BackendFloatPhase.expanded)
          Positioned.fill(
            child: Material(
              color: AppColors.background,
              child: SafeArea(child: widget.expandedBuilder(context)),
            ),
          ),
        if (phase == BackendFloatPhase.edge) _buildDraggableCircle(size, cfg),
      ],
    );
  }

  Widget _buildDraggableCircle(Size size, BackendFloatConfig cfg) {
    final pos = _resolveAnchor(size);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: _BackendFloatCircle(
        size: _circleSize,
        config: cfg,
        onDrag: (delta) {
          final base =
              widget.controller.floatAnchor ?? _defaultAnchor(size);
          widget.controller.setFloatAnchor(_clampAnchor(base + delta, size));
        },
        onTap: widget.controller.expandToCapsule,
      ),
    );
  }

  Widget _buildPositionedStrip(Size size, BackendFloatConfig cfg) {
    final layout = _capsuleLayout(size);
    return Positioned(
      left: layout.left,
      top: layout.top,
      width: layout.width,
      child: _BackendFloatStripBar(
        config: cfg,
        onOpenPanel: widget.controller.expandToPanel,
        onClose: widget.controller.close,
      ),
    );
  }
}

class _BackendFloatCircle extends StatelessWidget {
  const _BackendFloatCircle({
    required this.size,
    required this.config,
    required this.onDrag,
    required this.onTap,
  });

  final double size;
  final BackendFloatConfig config;
  final void Function(Offset delta) onDrag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onPanUpdate: (d) => onDrag(d.delta),
      child: Material(
        elevation: 6,
        shadowColor: Colors.black54,
        shape: const CircleBorder(),
        color: const Color(0xE6222226),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: config.iconBackground,
                  shape: BoxShape.circle,
                ),
                child: Icon(config.icon, color: Colors.white, size: 20),
              ),
              if (config.showCircleBadge)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackendFloatStripBar extends StatelessWidget {
  const _BackendFloatStripBar({
    required this.config,
    required this.onOpenPanel,
    required this.onClose,
  });

  final BackendFloatConfig config;
  final VoidCallback onOpenPanel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(28),
      color: const Color(0xE6222226),
      child: InkWell(
        onTap: onOpenPanel,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: config.iconBackground,
                  shape: BoxShape.circle,
                ),
                child: Icon(config.icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  config.stripTitle,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 20),
                color: AppColors.textMuted,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
