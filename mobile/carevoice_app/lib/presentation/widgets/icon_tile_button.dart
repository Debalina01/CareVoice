import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

class IconTileButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final Color? backgroundColor;
  final Color? iconColor;
  final double size;
  final double iconSize;
  final bool isCircular;
  final Widget? badge;

  const IconTileButton({
    super.key,
    required this.icon,
    this.onPressed,
    required this.tooltip,
    this.backgroundColor,
    this.iconColor,
    this.size = 46.0,
    this.iconSize = 22.0,
    this.isCircular = true,
    this.badge,
  });

  @override
  State<IconTileButton> createState() => _IconTileButtonState();
}

class _IconTileButtonState extends State<IconTileButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onPressed != null;
    final borderRadius = widget.isCircular
        ? BorderRadius.circular(AppRadius.circular)
        : BorderRadius.circular(AppRadius.control);

    return Semantics(
      label: widget.tooltip,
      button: true,
      enabled: isEnabled,
      child: Tooltip(
        message: widget.tooltip,
        child: MouseRegion(
          cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: AppDurations.hover,
                curve: Curves.easeOutCubic,
                width: widget.size,
                height: widget.size,
                transform: _isHovered && isEnabled
                    ? Matrix4.translationValues(0, -2, 0)
                    : Matrix4.identity(),
                decoration: BoxDecoration(
                  color: widget.backgroundColor ?? AppColors.creamLight,
                  borderRadius: borderRadius,
                  boxShadow: _isHovered && isEnabled ? AppShadows.lift : AppShadows.subtle,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: isEnabled ? widget.onPressed : null,
                    borderRadius: borderRadius,
                    child: Center(
                      child: Icon(
                        widget.icon,
                        size: widget.iconSize,
                        color: widget.iconColor ?? AppColors.forest,
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.badge != null)
                Positioned(
                  top: -3,
                  right: -3,
                  child: widget.badge!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
