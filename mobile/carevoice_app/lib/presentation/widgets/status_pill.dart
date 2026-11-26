import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

class StatusPill extends StatelessWidget {
  final String status;
  final String? displayLabel;
  final bool showDot;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const StatusPill({
    super.key,
    required this.status,
    this.displayLabel,
    this.showDot = true,
    this.fontSize = 11.5,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
  });

  Color _getStatusColor() {
    final lower = status.toLowerCase();
    if (lower.contains('take')) {
      return AppColors.taken;
    } else if (lower.contains('miss')) {
      return AppColors.missed;
    } else if (lower.contains('pend')) {
      return AppColors.pending;
    } else if (lower.contains('snooz')) {
      return AppColors.butter;
    } else if (lower.contains('skip')) {
      return AppColors.muted;
    }
    return AppColors.forest;
  }

  @override
  Widget build(BuildContext context) {
    final color = _getStatusColor();
    final label = displayLabel ?? status;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
