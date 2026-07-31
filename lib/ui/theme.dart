import 'package:flutter/material.dart';

/// Farbwelt der App — monochrom.
///
/// Zwei Paletten mit denselben semantischen Rollen: `light` ist weißes Papier
/// mit schwarzer Tinte, `dark` die Umkehrung. Keine Buntfarben: die Ordnung
/// entsteht über Linien, Flächenumkehr und Schriftgrade, nicht über Farbe —
/// was zur technischen Bildsprache aus ZENTRALE ohnehin besser passt als eine
/// Palette. Wer das ändern will, ändert es hier; die Zuordnung zu den Widgets
/// bleibt gleich.
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
    required this.onAccent,
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

  /// Was auf einer Akzentfläche steht — bei umgekehrter Darstellung.
  final Color onAccent;

  final Color error;

  /// Fläche hinter einer Fehlermeldung (ZENTRALE: `diff_del`).
  final Color errorBg;

  final Color warn;
  final Color ok;

  /// Fläche hinter einer Erfolgsmeldung (ZENTRALE: `diff_add`).
  final Color okBg;

  /// Die Akzentreihe, aus der Domänen ihre Farbe bekommen.
  final List<Color> accents;

  /// Weißes Blatt, schwarze Tinte.
  ///
  /// Die Graustufen sind reine Helligkeitsabstufungen von Schwarz — sie
  /// tragen die Hierarchie (Haupttext, Nebentext, Randnotiz), ohne Farbe
  /// einzuführen.
  static const light = Palette(
    brightness: Brightness.light,
    bg: Color(0xFFFFFFFF),
    bgAlt: Color(0xFFFFFFFF), // Kästen heben sich allein durch die Linie ab
    bgDim: Color(0xFFF4F4F4), // Eingabefelder, Hover
    bgSel: Color(0xFFE8E8E8),
    fg: Color(0xFF000000),
    fgDim: Color(0xFF4A4A4A),
    // Zielgerät ist ein Bigme Color, also Kaleido-Farb-E-Ink. Die
    // Farbfilterschicht kostet Kontrast, und Graustufen werden gerastert —
    // ein kleines mittelgraues Zeichen zerfällt dort, ein fast schwarzes
    // bleibt scharf. 0xFF8C8C8C ergab 3,4:1 und war unlesbar; das hier sind
    // 6,2:1. Wer den Ton wieder heller will, ändert ihn hier, nicht an den
    // Verwendungsstellen.
    fgFaint: Color(0xFF5F5F5F),
    border: Color(0xFF000000),
    accent: Color(0xFF000000),
    onAccent: Color(0xFFFFFFFF),
    error: Color(0xFF000000),
    errorBg: Color(0xFFF0F0F0),
    warn: Color(0xFF4A4A4A),
    ok: Color(0xFF000000),
    okBg: Color(0xFFF0F0F0),
    // Alle Domänen schwarz: unterschieden werden sie über ihren Namen im
    // eingekerbten Titel, nicht über einen Farbcode.
    accents: [Color(0xFF000000)],
  );

  /// Die Umkehrung — schwarzes Blatt, weiße Tinte.
  static const dark = Palette(
    brightness: Brightness.dark,
    bg: Color(0xFF000000),
    bgAlt: Color(0xFF000000),
    bgDim: Color(0xFF141414),
    bgSel: Color(0xFF242424),
    fg: Color(0xFFFFFFFF),
    fgDim: Color(0xFFB4B4B4),
    fgFaint: Color(0xFF909090),
    border: Color(0xFFFFFFFF),
    accent: Color(0xFFFFFFFF),
    onAccent: Color(0xFF000000),
    error: Color(0xFFFFFFFF),
    errorBg: Color(0xFF1A1A1A),
    warn: Color(0xFFB4B4B4),
    ok: Color(0xFFFFFFFF),
    okBg: Color(0xFF1A1A1A),
    accents: [Color(0xFFFFFFFF)],
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
  /// zuletzt gebaute Palette zeigen — im hellen Modus käme die dunkle heraus.
  static Palette paletteOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? Palette.dark
      : Palette.light;

  static ThemeData light() => build(Palette.light);

  static ThemeData dark() => build(Palette.dark);

  static ThemeData build(Palette p) {
    final onAccent = p.onAccent;

    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.accent,
      onPrimary: onAccent,
      // Fläche für die Rückmeldung nach einem Import.
      primaryContainer: p.okBg,
      onPrimaryContainer: p.fg,
      secondary: p.accent,
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
      labelMedium: s(
        10.5,
        w: FontWeight.w700,
        track: Metrics.trackWider,
        c: p.fgFaint,
      ),
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
