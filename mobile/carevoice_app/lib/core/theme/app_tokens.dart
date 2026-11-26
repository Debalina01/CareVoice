import 'package:flutter/material.dart';

/// Corner radius tokens matching the soft clay aesthetic.
class AppRadius {
  AppRadius._();

  static const double card = 28.0;
  static const double control = 20.0;
  static const double pill = 999.0;
  static const double circular = 999.0;
  static const double modal = 32.0;
  static const double sm = 12.0;
  static const double md = 16.0;

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(card));
  static const BorderRadius controlRadius = BorderRadius.all(Radius.circular(control));
  static const BorderRadius pillRadius = BorderRadius.all(Radius.circular(pill));
  static const BorderRadius modalRadius = BorderRadius.all(Radius.circular(modal));
}

/// Spacing and breakpoint tokens.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
}

class AppBreakpoints {
  AppBreakpoints._();

  static const double mobile = 600.0;
  static const double desktop = 1100.0;

  static bool isMobile(double width) => width < mobile;
  static bool isTablet(double width) => width >= mobile && width < desktop;
  static bool isDesktop(double width) => width >= desktop;
}

class AppDimensions {
  AppDimensions._();

  static const double sidebarWidth = 260.0;
  static const double railWidth = 88.0;
  static const double minTouchTarget = 48.0;
}

/// Clay depth shadows (warm shadow below + white highlight above).
class AppShadows {
  AppShadows._();

  /// Standard soft clay card shadow
  static const List<BoxShadow> clay = [
    BoxShadow(
      color: Color(0x184A3B2F),
      blurRadius: 18,
      offset: Offset(0, 8),
      spreadRadius: 0,
    ),
    BoxShadow(
      color: Color(0xCCFFFFFF),
      blurRadius: 10,
      offset: Offset(-3, -3),
      spreadRadius: 0,
    ),
  ];

  /// Subtle elevation for smaller chips, buttons, badges
  static const List<BoxShadow> subtle = [
    BoxShadow(
      color: Color(0x104A3B2F),
      blurRadius: 10,
      offset: Offset(0, 4),
      spreadRadius: 0,
    ),
    BoxShadow(
      color: Color(0x99FFFFFF),
      blurRadius: 6,
      offset: Offset(-2, -2),
      spreadRadius: 0,
    ),
  ];

  /// Lifted state for hover or active selection
  static const List<BoxShadow> lift = [
    BoxShadow(
      color: Color(0x224A3B2F),
      blurRadius: 24,
      offset: Offset(0, 12),
      spreadRadius: 1,
    ),
    BoxShadow(
      color: Color(0xE6FFFFFF),
      blurRadius: 12,
      offset: Offset(-3, -3),
      spreadRadius: 0,
    ),
  ];

  /// Pressed / sunken state
  static const List<BoxShadow> pressed = [
    BoxShadow(
      color: Color(0x124A3B2F),
      blurRadius: 4,
      offset: Offset(0, 2),
      spreadRadius: 0,
    ),
  ];
}

class AppDurations {
  AppDurations._();

  static const Duration hover = Duration(milliseconds: 160);
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration normal = Duration(milliseconds: 300);
}

class AppTokens {
  AppTokens._();

  static const List<BoxShadow> clayShadowSm = AppShadows.subtle;
  static const List<BoxShadow> clayShadowMd = AppShadows.clay;
  static const List<BoxShadow> clayShadowLg = AppShadows.lift;
}

