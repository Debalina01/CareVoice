import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

enum PillButtonVariant {
  primary,
  secondary,
  tinted,
  subtle,
  outlined,
}

class PillButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final PillButtonVariant variant;
  final bool isLoading;
  final double? width;
  final double height;
  final Color? customColor;
  final Color? customTextColor;
  final String? semanticsLabel;

  const PillButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon,
    this.variant = PillButtonVariant.primary,
    this.isLoading = false,
    this.width,
    this.height = 48.0,
    this.customColor,
    this.customTextColor,
    this.semanticsLabel,
  });

  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton> {
  bool _isHovered = false;

  Color _getBackgroundColor() {
    if (widget.customColor != null) return widget.customColor!;
    switch (widget.variant) {
      case PillButtonVariant.primary:
        return AppColors.coral;
      case PillButtonVariant.secondary:
        return AppColors.forest;
      case PillButtonVariant.tinted:
        return AppColors.sage;
      case PillButtonVariant.subtle:
        return AppColors.creamLight;
      case PillButtonVariant.outlined:
        return Colors.transparent;
    }
  }

  Color _getTextColor() {
    if (widget.customTextColor != null) return widget.customTextColor!;
    switch (widget.variant) {
      case PillButtonVariant.primary:
      case PillButtonVariant.secondary:
        return Colors.white;
      case PillButtonVariant.tinted:
      case PillButtonVariant.subtle:
        return AppColors.ink;
      case PillButtonVariant.outlined:
        return AppColors.forest;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onPressed != null && !widget.isLoading;
    final bgColor = _getBackgroundColor();
    final textColor = _getTextColor();

    final shadows = widget.variant == PillButtonVariant.subtle || widget.variant == PillButtonVariant.primary
        ? (_isHovered && isEnabled ? AppShadows.lift : AppShadows.subtle)
        : null;

    final border = widget.variant == PillButtonVariant.outlined
        ? Border.all(color: AppColors.forest, width: 1.5)
        : null;

    return Semantics(
      label: widget.semanticsLabel ?? widget.label,
      button: true,
      enabled: isEnabled,
      child: MouseRegion(
        cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: AppDurations.hover,
          curve: Curves.easeOutCubic,
          width: widget.width,
          height: widget.height,
          transform: _isHovered && isEnabled
              ? Matrix4.translationValues(0, -2, 0)
              : Matrix4.identity(),
          decoration: BoxDecoration(
            color: isEnabled ? bgColor : bgColor.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: isEnabled ? shadows : null,
            border: border,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isEnabled ? widget.onPressed : null,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Center(
                  child: widget.isLoading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation<Color>(textColor),
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (widget.icon != null) ...[
                              Icon(widget.icon, size: 18, color: textColor),
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Text(
                                widget.label,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.trailingIcon != null) ...[
                              const SizedBox(width: 8),
                              Icon(widget.trailingIcon, size: 18, color: textColor),
                            ],
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
