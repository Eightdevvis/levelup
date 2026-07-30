import 'package:flutter/material.dart';

/// Farbwelt der App.
///
/// Dunkel als Standard, weil die App beim Üben danebenliegt — im Proberaum,
/// im Gym, am Zeichentisch — und nicht blenden soll.
class AppTheme {
  static const _seed = Color(0xFF7C6BF0);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    ).copyWith(
      surface: const Color(0xFF121116),
    );

    return _base(scheme);
  }

  static ThemeData light() => _base(
        ColorScheme.fromSeed(seedColor: _seed).copyWith(
          surface: const Color(0xFFFBFAFF),
        ),
      );

  static ThemeData _base(ColorScheme scheme) => ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: scheme.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: scheme.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          margin: EdgeInsets.zero,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        chipTheme: ChipThemeData(
          side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );

  /// Jede Domäne bekommt eine stabile Farbe, ohne dass die App die Domänen
  /// kennen muss — sonst müsste bei jeder neuen Disziplin Code angefasst
  /// werden, und genau das soll die App ja nicht.
  static Color domainColor(String domain) {
    const palette = [
      Color(0xFF7C6BF0), // violett
      Color(0xFF34B9A0), // türkis
      Color(0xFFE0844A), // orange
      Color(0xFF4A93E0), // blau
      Color(0xFFD2618E), // magenta
      Color(0xFF8CB84A), // grün
      Color(0xFFC9A227), // gold
    ];
    var hash = 0;
    for (final unit in domain.toLowerCase().codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return palette[hash % palette.length];
  }
}

/// Sekunden als "12:05" bzw. "45s".
String formatDuration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  if (rest == 0) return '$minutes min';
  return '$minutes:${rest.toString().padLeft(2, '0')}';
}
