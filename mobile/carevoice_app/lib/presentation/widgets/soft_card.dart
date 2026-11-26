import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

/// A soft pastel "clay" card featuring warm depth shadows and hover elevation.
class SoftCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final double radius;
  final VoidCallback? onTap;
  final bool enableHoverLift;
  final List<BoxShadow>? customShadows;
  final Border? border;

  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.backgroundColor,
    this.radius = AppRadius.card,
    this.onTap,
    this.enableHoverLift = true,
    this.customShadows,
    this.border,
  });

  @override
  State<SoftCard> createState() => _SoftCardState();
}

class _SoftCardState extends State<SoftCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isInteractive = widget.onTap != null;
    final borderRadius = BorderRadius.circular(widget.radius);

    final shadows = widget.customShadows ??
        (_isHovered && isInteractive && widget.enableHoverLift
            ? AppShadows.lift
            : AppShadows.clay);

    final cardWidget = AnimatedContainer(
      duration: AppDurations.hover,
      curve: Curves.easeOutCubic,
      transform: _isHovered && isInteractive && widget.enableHoverLift
          ? Matrix4.translationValues(0, -3, 0)
          : Matrix4.identity(),
      decoration: BoxDecoration(
        color: widget.backgroundColor ?? AppColors.creamLight,
        borderRadius: borderRadius,
        boxShadow: shadows,
        border: widget.border,
      ),
      child: Padding(
        padding: widget.padding,
        child: widget.child,
      ),
    );

    if (!isInteractive) return cardWidget;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: cardWidget,
      ),
    );
  }
}
