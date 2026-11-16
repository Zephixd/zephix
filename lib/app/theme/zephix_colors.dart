import 'package:flutter/material.dart';

/// Zephix brand palette exposed as a [ThemeExtension] so every widget reads
/// colours from the theme instead of hard-coding them.
@immutable
class ZephixColors extends ThemeExtension<ZephixColors> {
  const ZephixColors({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.primary,
    required this.primaryDark,
    required this.secondary,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
  });

  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color primary;
  final Color primaryDark;
  final Color secondary;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;

  static const dark = ZephixColors(
    background: Color(0xFF090D0B),
    surface: Color(0xFF111914),
    surfaceElevated: Color(0xFF19231D),
    primary: Color(0xFF80E6AD),
    primaryDark: Color(0xFF42B97B),
    secondary: Color(0xFFB7A4F4),
    textPrimary: Color(0xFFF4F7F4),
    textSecondary: Color(0xFF929D95),
    border: Color(0xFF253129),
  );

  static const light = ZephixColors(
    background: Color(0xFFF4F7F4),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFE8EFE9),
    primary: Color(0xFF1E8A55),
    primaryDark: Color(0xFF156B41),
    secondary: Color(0xFF6A55C4),
    textPrimary: Color(0xFF0B120E),
    textSecondary: Color(0xFF56635A),
    border: Color(0xFFD3DDD5),
  );

  ZephixColors withAccent(AccentChoice accent, Brightness brightness) {
    if (accent == AccentChoice.mint) return this;
    final c = brightness == Brightness.dark ? accent.dark : accent.light;
    return copyWith(primary: c, primaryDark: Color.lerp(c, Colors.black, 0.25));
  }

  @override
  ZephixColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? primary,
    Color? primaryDark,
    Color? secondary,
    Color? textPrimary,
    Color? textSecondary,
    Color? border,
  }) {
    return ZephixColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      primary: primary ?? this.primary,
      primaryDark: primaryDark ?? this.primaryDark,
      secondary: secondary ?? this.secondary,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      border: border ?? this.border,
    );
  }

  @override
  ZephixColors lerp(ThemeExtension<ZephixColors>? other, double t) {
    if (other is! ZephixColors) return this;
    return ZephixColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      border: Color.lerp(border, other.border, t)!,
    );
  }
}

/// User-selectable accent colours (Ajustes → Apariencia).
enum AccentChoice {
  mint('Menta', Color(0xFF80E6AD), Color(0xFF1E8A55)),
  lavender('Lavanda', Color(0xFFB7A4F4), Color(0xFF6A55C4)),
  amber('Ámbar', Color(0xFFF2C46D), Color(0xFF9A6A0E)),
  coral('Coral', Color(0xFFF39A8E), Color(0xFFB4473A)),
  sky('Cielo', Color(0xFF8ED0F5), Color(0xFF1F6F9C));

  const AccentChoice(this.label, this.dark, this.light);
  final String label;
  final Color dark;
  final Color light;

  static AccentChoice fromName(String? name) =>
      AccentChoice.values.firstWhere((a) => a.name == name, orElse: () => AccentChoice.mint);
}

extension ZephixThemeX on BuildContext {
  ZephixColors get zc => Theme.of(this).extension<ZephixColors>()!;
  TextTheme get tt => Theme.of(this).textTheme;
}
