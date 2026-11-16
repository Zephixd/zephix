import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'zephix_colors.dart';

/// Spacing, radius and motion tokens of the Zephix design system.
abstract final class ZSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const page = 20.0;
}

abstract final class ZRadius {
  static const sm = 8.0;
  static const md = 14.0;
  static const lg = 22.0;
  static const pill = 999.0;
}

abstract final class ZMotion {
  static const fast = Duration(milliseconds: 160);
  static const medium = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 480);
  static const curve = Curves.easeOutCubic;
}

class ZephixTheme {
  static ThemeData build(Brightness brightness, AccentChoice accent) {
    final base = brightness == Brightness.dark ? ZephixColors.dark : ZephixColors.light;
    final c = base.withAccent(accent, brightness);
    final onPrimary = brightness == Brightness.dark ? c.background : Colors.white;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: onPrimary,
      secondary: c.secondary,
      onSecondary: c.background,
      error: const Color(0xFFF2797B),
      onError: Colors.black,
      surface: c.surface,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      surfaceContainerHighest: c.surfaceElevated,
      surfaceContainerHigh: c.surfaceElevated,
      surfaceContainer: c.surface,
      outline: c.border,
      outlineVariant: c.border,
    );

    final text = _textTheme(c);
    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZRadius.md));
    final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZRadius.pill));
    OutlineInputBorder field(Color color, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(ZRadius.md),
          borderSide: BorderSide(color: color, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      textTheme: text,
      extensions: [c],
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent)
            : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZRadius.md),
          side: BorderSide(color: c.border),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: c.textSecondary,
        textColor: c.textPrimary,
        contentPadding: const EdgeInsets.symmetric(horizontal: ZSpace.page),
      ),
      iconTheme: IconThemeData(color: c.textPrimary),
      chipTheme: ChipThemeData(
        backgroundColor: c.surface,
        selectedColor: c.primary.withValues(alpha: 0.18),
        side: BorderSide(color: c.border),
        labelStyle: text.labelLarge,
        shape: pill,
        showCheckmark: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        hintStyle: text.bodyLarge?.copyWith(color: c.textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: ZSpace.lg, vertical: 14),
        border: field(c.border),
        enabledBorder: field(c.border),
        focusedBorder: field(c.primary, 1.5),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: onPrimary,
          textStyle: text.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: ZSpace.xl, vertical: 14),
          shape: pill,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          side: BorderSide(color: c.border),
          textStyle: text.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: ZSpace.xl, vertical: 14),
          shape: pill,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: c.primary, textStyle: text.labelLarge),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: c.primary,
        inactiveTrackColor: c.border,
        thumbColor: c.textPrimary,
        overlayColor: c.primary.withValues(alpha: 0.12),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.border,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(ZRadius.lg)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZRadius.lg)),
        titleTextStyle: text.titleLarge,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceElevated,
        contentTextStyle: text.bodyMedium,
        behavior: SnackBarBehavior.floating,
        shape: rounded,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? onPrimary : c.textSecondary),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.primary : c.surfaceElevated),
        trackOutlineColor: WidgetStatePropertyAll(c.border),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.textPrimary,
        unselectedLabelColor: c.textSecondary,
        indicatorColor: c.primary,
        dividerColor: Colors.transparent,
        labelStyle: text.labelLarge,
        tabAlignment: TabAlignment.start,
      ),
      popupMenuTheme: PopupMenuThemeData(color: c.surfaceElevated, shape: rounded),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary),
    );
  }

  /// Editorial type scale: tight, heavy display styles for headlines and
  /// calm, readable body text. Uses the platform sans-serif (Roboto on
  /// Android) so no font is ever fetched from the network.
  static TextTheme _textTheme(ZephixColors c) {
    TextStyle s(double size, FontWeight w, {double ls = 0, double h = 1.25, Color? color}) =>
        TextStyle(
          fontSize: size,
          fontWeight: w,
          letterSpacing: ls,
          height: h,
          color: color ?? c.textPrimary,
        );
    return TextTheme(
      displayLarge: s(48, FontWeight.w800, ls: -1.6, h: 1.05),
      displayMedium: s(38, FontWeight.w800, ls: -1.2, h: 1.08),
      displaySmall: s(30, FontWeight.w800, ls: -0.8, h: 1.1),
      headlineLarge: s(28, FontWeight.w700, ls: -0.6),
      headlineMedium: s(24, FontWeight.w700, ls: -0.4),
      headlineSmall: s(20, FontWeight.w700, ls: -0.2),
      titleLarge: s(19, FontWeight.w700, ls: -0.2),
      titleMedium: s(16, FontWeight.w600),
      titleSmall: s(14, FontWeight.w600),
      bodyLarge: s(16, FontWeight.w400, h: 1.45),
      bodyMedium: s(14, FontWeight.w400, h: 1.4),
      bodySmall: s(12.5, FontWeight.w400, h: 1.35, color: c.textSecondary),
      labelLarge: s(14, FontWeight.w600, ls: 0.1),
      labelMedium: s(12, FontWeight.w600, ls: 0.4, color: c.textSecondary),
      labelSmall: s(11, FontWeight.w700, ls: 1.1, color: c.textSecondary),
    );
  }
}
