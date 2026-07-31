import 'package:flutter/material.dart';

/// Farbwelt der App — übernommen aus ZENTRALE
/// (`nvim/lua/zentrale_theme/palettes.lua`).
///
/// Zwei Paletten mit denselben semantischen Rollen: `paper` (hell) ist das
/// warme Sepia-Papier mit botanischen Akzenten, `cyber` (dunkel) echtes
/// Schwarz mit Neon. Wer eine Farbe ändern will, ändert sie hier — die
/// Zuordnung zu den Widgets bleibt gleich.
class Palette {
  const Palette({
    required this.brightness,
    required this.bg,
    required this.bgAlt,
    required this.bgDim,
    required this.bgSel,
    required this.fg,
    required this.fgDim,
    required this.fgFaint,
    required this.border,
    required this.accent,
    required this.error,
    required this.errorBg,
    required this.warn,
    required this.ok,
    required this.okBg,
    required this.accents,
  });

  final Brightness brightness;

  /// Grundfläche.
  final Color bg;

  /// Karton — Karten, Dialoge, abgesetzte Flächen.
  final Color bgAlt;

  /// Leicht abgesetzt — Hover, Zeilenhinterlegung.
  final Color bgDim;

  /// Auswahl.
  final Color bgSel;

  final Color fg;
  final Color fgDim;

  /// Verblasster Bleistift — Nebeninformation.
  final Color fgFaint;

  final Color border;

  /// Leitfarbe für Bedienelemente.
  final Color accent;

  final Color error;

  /// Fläche hinter einer Fehlermeldung (ZENTRALE: `diff_del`).
  final Color errorBg;

  final Color warn;
  final Color ok;

  /// Fläche hinter einer Erfolgsmeldung (ZENTRALE: `diff_add`).
  final Color okBg;

  /// Die Akzentreihe, aus der Domänen ihre Farbe bekommen.
  final List<Color> accents;

  /// „paper" — warmes Sepia-Papier, Akzente aus dem Garten.
  static const paper = Palette(
    brightness: Brightness.light,
    bg: Color(0xFFECE0C0), // Sepia-Papier
    bgAlt: Color(0xFFE2D4AE), // Karton
    bgDim: Color(0xFFE6DAB6),
    bgSel: Color(0xFFD8DCAE), // Blattschatten
    fg: Color(0xFF33291C), // Sepia-Tinte
    fgDim: Color(0xFF5F563F),
    fgFaint: Color(0xFF6E6551), // verblasster Bleistift
    border: Color(0xFFC4B590),
    accent: Color(0xFF2F5F7D), // Wasser-Indigo
    error: Color(0xFF972920), // Rost
    errorBg: Color(0xFFECCDBE),
    warn: Color(0xFF765C14), // Pollen
    ok: Color(0xFF44661D), // Blattgrün
    okBg: Color(0xFFD5E2B2),
    accents: [
      Color(0xFF2F5F7D), // Wasser-Indigo
      Color(0xFF44661D), // Blattgrün
      Color(0xFF934726), // Terracotta
      Color(0xFF8A3357), // Beere
      Color(0xFF2F5A33), // Tannentiefe
      Color(0xFF785222), // Rinde
      Color(0xFF3A664B), // Salbei
    ],
  );

  /// „cyber" — echtes Schwarz, Neon-Palette.
  static const cyber = Palette(
    brightness: Brightness.dark,
    bg: Color(0xFF000000),
    bgAlt: Color(0xFF05080A),
    bgDim: Color(0xFF070D10),
    bgSel: Color(0xFF16333D),
    fg: Color(0xFFCCF7FF),
    fgDim: Color(0xFF7FB3BF),
    fgFaint: Color(0xFF577C8A),
    border: Color(0xFF123039),
    accent: Color(0xFF00F0FF), // Neon-Cyan
    error: Color(0xFFFF2F5E),
    errorBg: Color(0xFF2A0812),
    warn: Color(0xFFFFE93D),
    ok: Color(0xFF00FF9C),
    okBg: Color(0xFF06251C),
    accents: [
      Color(0xFF00F0FF), // Cyan
      Color(0xFF00FF9C), // Spring
      Color(0xFFFF7A18), // Orange
      Color(0xFFFF2BD6), // Magenta
      Color(0xFFFFE93D), // Gelb
      Color(0xFFA56BFF), // Violett
      Color(0xFF38BDFF), // Azur
    ],
  );
}

/// Maße der ZENTRALE-Bildsprache (`ui/templates/monolith.html`).
///
/// Kein Material-Look: scharfe Rechtecke mit Haarlinie, Titel in die obere
/// Kante eingekerbt, Beschriftungen in Versalien mit weiter Laufweite,
/// gepunktete Trennlinien, aktive Zustände invertiert.
class Metrics {
  /// Es gibt keine Rundungen. Das ist der auffälligste Unterschied zu Material.
  static const radius = 0.0;

  static const line = 1.0;

  /// `.box { padding: 23px 15px 12px }` — oben mehr, weil dort der Titel sitzt.
  static const boxPadding = EdgeInsets.fromLTRB(15, 22, 15, 13);

  /// Laufweite der Versalien-Labels (`letter-spacing: 0.14em` bei ~11px).
  static const trackWide = 1.6;
  static const trackWider = 2.6;

  static const mono = 'JetBrainsMono';

  /// Für Ziffern, die wie auf einem Messgerät stehen sollen.
  static const display = 'VT323';
}

class AppTheme {
  /// Die Palette, die für diesen Teil des Baums gilt.
  ///
  /// Bewusst aus dem Kontext abgeleitet und nicht global gemerkt: `theme` und
  /// `darkTheme` werden beide gebaut, ein globaler Merker würde also immer die
  /// zuletzt gebaute Palette zeigen — und damit im hellen Modus die
  /// Neon-Farben.
  static Palette paletteOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Palette.cyber
          : Palette.paper;

  static ThemeData light() => build(Palette.paper);

  static ThemeData dark() => build(Palette.cyber);

  static ThemeData build(Palette p) {
    final onAccent = p.brightness == Brightness.light
        ? const Color(0xFFF4ECD6) // helles Papier auf dunkler Tinte
        : p.bg;

    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.accent,
      onPrimary: onAccent,
      // Erfolgs-/Hinweisfläche: auf Papier der Blattschatten, im Cyber-Modus
      // der Diff-Grünton. Wird für die Rückmeldung nach einem Import benutzt.
      primaryContainer: p.okBg,
      onPrimaryContainer: p.fg,
      secondary: p.accents[1],
      onSecondary: onAccent,
      secondaryContainer: p.bgSel,
      onSecondaryContainer: p.fg,
      error: p.error,
      onError: onAccent,
      errorContainer: p.errorBg,
      onErrorContainer: p.brightness == Brightness.light ? p.fg : p.error,
      surface: p.bg,
      onSurface: p.fg,
      surfaceContainerHighest: p.bgAlt,
      outline: p.border,
      outlineVariant: p.border,
    );

    const sharp = RoundedRectangleBorder(borderRadius: BorderRadius.zero);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: Metrics.mono,
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.bg,
      dividerColor: p.border,
      dividerTheme: DividerThemeData(color: p.border, space: 1, thickness: 1),
      textTheme: _textTheme(p),
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        foregroundColor: p.fg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: Metrics.mono,
          color: p.fg,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: Metrics.trackWide,
        ),
      ),
      // Kein Karton mehr: eine Haarlinie um eine flache Fläche, scharfkantig.
      cardTheme: CardThemeData(
        elevation: 0,
        color: p.bgAlt,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: p.border, width: Metrics.line),
        ),
        margin: EdgeInsets.zero,
      ),
      // Aktiver Zustand invertiert — wie `.theme-ctl button.on` in ZENTRALE.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: onAccent,
          disabledBackgroundColor: p.bgDim,
          disabledForegroundColor: p.fgFaint,
          minimumSize: const Size.fromHeight(46),
          shape: sharp,
          textStyle: const TextStyle(
            fontFamily: Metrics.mono,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: Metrics.trackWide,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.accent,
          side: BorderSide(color: p.border, width: Metrics.line),
          minimumSize: const Size.fromHeight(42),
          shape: sharp,
          textStyle: const TextStyle(
            fontFamily: Metrics.mono,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: Metrics.trackWide,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.accent,
          shape: sharp,
          textStyle: const TextStyle(
            fontFamily: Metrics.mono,
            fontSize: 12,
            letterSpacing: Metrics.trackWide,
          ),
        ),
      ),
      iconTheme: IconThemeData(color: p.fgDim, size: 20),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 15, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.bgDim,
        hintStyle: TextStyle(color: p.fgFaint, fontFamily: Metrics.mono),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: p.border, width: Metrics.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: p.border, width: Metrics.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: p.accent, width: Metrics.line),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.bgDim,
        circularTrackColor: p.bgDim,
        linearMinHeight: 3,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.fg,
        contentTextStyle: TextStyle(
          color: p.bg,
          fontFamily: Metrics.mono,
          fontSize: 12,
          letterSpacing: 0.6,
        ),
        behavior: SnackBarBehavior.floating,
        shape: sharp,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.bg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: p.border, width: Metrics.line),
        ),
        titleTextStyle: TextStyle(
          fontFamily: Metrics.mono,
          color: p.fg,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: Metrics.trackWide,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.bg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: p.border, width: Metrics.line),
        ),
        textStyle: TextStyle(
          fontFamily: Metrics.mono,
          color: p.fg,
          fontSize: 12,
          letterSpacing: 0.8,
        ),
      ),
      chipTheme: const ChipThemeData(side: BorderSide.none, shape: sharp),
    );
  }

  static TextTheme _textTheme(Palette p) {
    TextStyle s(double size, {FontWeight? w, double track = 0, Color? c}) =>
        TextStyle(
          fontFamily: Metrics.mono,
          fontSize: size,
          fontWeight: w,
          letterSpacing: track,
          color: c ?? p.fg,
          height: 1.5,
        );

    return TextTheme(
      titleLarge: s(17, w: FontWeight.w700, track: Metrics.trackWide),
      titleMedium: s(14, w: FontWeight.w700, track: 0.8),
      bodyLarge: s(13),
      bodyMedium: s(12.5),
      bodySmall: s(11.5, c: p.fgDim),
      labelLarge: s(12, w: FontWeight.w500, track: Metrics.trackWide),
      labelMedium: s(10.5, w: FontWeight.w700, track: Metrics.trackWider, c: p.fgFaint),
    );
  }

  /// Jede Domäne bekommt eine stabile Farbe aus der Akzentreihe, ohne dass die
  /// App die Domänen kennen muss — sonst müsste bei jeder neuen Disziplin Code
  /// angefasst werden, und genau das soll die App ja nicht.
  ///
  /// Der Index bleibt über beide Paletten gleich: eine Domäne, die auf Papier
  /// Terracotta ist, ist im Cyber-Modus Orange — dieselbe Position der Reihe.
  static Color domainColor(BuildContext context, String domain) {
    final accents = paletteOf(context).accents;
    var hash = 0;
    for (final unit in domain.toLowerCase().codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return accents[hash % accents.length];
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
