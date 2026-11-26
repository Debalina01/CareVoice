import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

class AvatarBadge extends StatelessWidget {
  final String name;
  final String? relation;
  final double size;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool showRelationBadge;

  const AvatarBadge({
    super.key,
    required this.name,
    this.relation,
    this.size = 44.0,
    this.backgroundColor,
    this.foregroundColor,
    this.showRelationBadge = false,
  });

  String get _initials {
    final clean = name.trim();
    if (clean.isEmpty) return 'U';
    final parts = clean.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return clean[0].toUpperCase();
  }

  Color _pickColorFromName() {
    final palette = [
      AppColors.sage,
      AppColors.mint,
      AppColors.peach,
      AppColors.powder,
      AppColors.butter,
    ];
    int hash = 0;
    for (int i = 0; i < name.length; i++) {
      hash = (hash + name.codeUnitAt(i)) % palette.length;
    }
    return palette[hash];
  }

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? _pickColorFromName();
    final fg = foregroundColor ?? AppColors.ink;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            boxShadow: AppShadows.subtle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Center(
            child: Text(
              _initials,
              style: TextStyle(
                color: fg,
                fontSize: size * 0.42,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ),
        if (showRelationBadge && relation != null && relation!.isNotEmpty)
          Positioned(
            bottom: -3,
            right: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.forest,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                relation!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
