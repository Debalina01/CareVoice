import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_tokens.dart';

class AppTheme {
  AppTheme._();

  static const List<String> fontFallback = [
    'Noto Sans Bengali',
    'NotoSansBengali',
    'SolaimanLipi',
    'Kalpurush',
    'sans-serif',
  ];

  static ThemeData get light {
    final nunitoFamily = GoogleFonts.nunito().fontFamily;

    final textTheme = TextTheme(
      displayLarge: TextStyle(
        fontFamily: nunitoFamily,
        fontFamilyFallback: fontFallback,
        fontSize: 34,
        fontWeight: FontWeight.w900,
        color: AppColors.ink,
        letterSpacing: -0.5,
      ),
      displayMedium: TextStyle(
        fontFamily: nunitoFamily,
        fontFamilyFallback: fontFallback,
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
        letterSpacing: -0.3,
      ),
      displaySmall: TextStyle(
        fontFamily: nunitoFamily,
        fontFamilyFallback: fontFallback,
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
      headlineMedium: TextStyle(
        fontFamily: nunitoFamily,
        fontFamilyFallback: fontFallback,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
      headlineSmall: TextStyle(
        fontFamily: nunitoFamily,
        fontFamilyFallback: fontFallback,
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
      titleLarge: TextStyle(
        fontFamily: nunitoFamily,
        fontFamilyFallback: fontFallback,
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
      titleMedium: TextStyle(
        fontFamily: nunitoFamily,
        fontFamilyFallback: fontFallback,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      titleSmall: TextStyle(
        fontFamily: nunitoFamily,
        fontFamilyFallback: fontFallback,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.muted,
      ),
      bodyLarge: TextStyle(
        fontFamily: nunitoFamily,
        fontFamilyFallback: fontFallback,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      bodyMedium: TextStyle(
        fontFamily: nunitoFamily,
        fontFamilyFallback: fontFallback,
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
        color: AppColors.ink,
      ),
      bodySmall: TextStyle(
        fontFamily: nunitoFamily,
        fontFamilyFallback: fontFallback,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.muted,
      ),
      labelLarge: TextStyle(
        fontFamily: nunitoFamily,
        fontFamilyFallback: fontFallback,
        fontSize: 14,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
      labelMedium: TextStyle(
        fontFamily: nunitoFamily,
        fontFamilyFallback: fontFallback,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      labelSmall: TextStyle(
        fontFamily: nunitoFamily,
        fontFamilyFallback: fontFallback,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.muted,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.cream,
      fontFamily: nunitoFamily,
      fontFamilyFallback: fontFallback,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: AppColors.forest,
        onPrimary: Colors.white,
        secondary: AppColors.coral,
        onSecondary: Colors.white,
        tertiary: AppColors.sage,
        onTertiary: AppColors.ink,
        surface: AppColors.creamLight,
        onSurface: AppColors.ink,
        error: AppColors.missed,
        onError: Colors.white,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppColors.forest),
        titleTextStyle: TextStyle(
          fontFamily: nunitoFamily,
          fontFamilyFallback: fontFallback,
          fontSize: 20,
          fontWeight: FontWeight.w900,
          color: AppColors.ink,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.creamLight,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.creamLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.modal),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.creamLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        hintStyle: TextStyle(
          fontFamily: nunitoFamily,
          fontFamilyFallback: fontFallback,
          color: AppColors.muted,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        labelStyle: TextStyle(
          fontFamily: nunitoFamily,
          fontFamilyFallback: fontFallback,
          color: AppColors.muted,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.softBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.forest, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.missed, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.missed, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.coral,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: const StadiumBorder(),
          textStyle: TextStyle(
            fontFamily: nunitoFamily,
            fontFamilyFallback: fontFallback,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.forest,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          shape: const StadiumBorder(),
          textStyle: TextStyle(
            fontFamily: nunitoFamily,
            fontFamilyFallback: fontFallback,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.forest,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          side: const BorderSide(color: AppColors.forest, width: 1.5),
          shape: const StadiumBorder(),
          textStyle: TextStyle(
            fontFamily: nunitoFamily,
            fontFamilyFallback: fontFallback,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.forest,
          shape: const StadiumBorder(),
          textStyle: TextStyle(
            fontFamily: nunitoFamily,
            fontFamilyFallback: fontFallback,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.creamLight,
        selectedColor: AppColors.sage,
        disabledColor: Colors.grey.shade200,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: const StadiumBorder(),
        side: BorderSide.none,
        labelStyle: TextStyle(
          fontFamily: nunitoFamily,
          fontFamilyFallback: fontFallback,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.creamLight,
        modalBackgroundColor: AppColors.creamLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.modal)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.sage,
        elevation: 0,
        indicatorColor: AppColors.cream,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontFamily: nunitoFamily,
              fontFamilyFallback: fontFallback,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: AppColors.forest,
            );
          }
          return TextStyle(
            fontFamily: nunitoFamily,
            fontFamilyFallback: fontFallback,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          );
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: TextStyle(
          fontFamily: nunitoFamily,
          fontFamilyFallback: fontFallback,
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: AppColors.creamLight,
        headerBackgroundColor: AppColors.forest,
        headerForegroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.modal),
        ),
      ),
    );
  }
}
