import 'package:flutter/material.dart';

import 'theme.dart';

/// Die Box aus ZENTRALE (`.box` + `.bt` + `.bt2` in `monolith.html`).
///
/// Scharfkantiger Rahmen aus einer Haarlinie, dessen obere Kante vom Titel
/// durchstoßen wird — der Titel sitzt *in* der Linie, nicht darüber, und ist
/// von Box-Drawing-Zeichen eingefasst. Rechts oben kann eine Nebenangabe
/// stehen. Das ist das prägendste Element der Vorlage.
class ZBox extends StatelessWidget {
  const ZBox({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.accent,
    this.onTap,
    this.padding,
    this.filled = true,
  });

  final Widget child;

  /// Erscheint eingekerbt in der oberen Kante, in Versalien.
  final String? title;

  /// Nebenangabe rechts oben, ebenfalls in die Kante gesetzt.
  final String? trailing;

  /// Farbe des Titels. Ohne Angabe die Leitfarbe der Palette.
  final Color? accent;

  final VoidCallback? onTap;
  final EdgeInsets? padding;

  /// Flächen-Füllung. Ohne sie steht die Box nur als Linie auf dem Papier.
  final bool filled;

  static const _notchInset = 13.0;
  static const _notchHalf = 8.0;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    final tone = accent ?? p.accent;
    final inner = Padding(
      padding: padding ?? Metrics.boxPadding,
      child: SizedBox(width: double.infinity, child: child),
    );

    final Widget box = Material(
      color: filled ? p.bgAlt : Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: p.border, width: Metrics.line),
      ),
      child: onTap == null ? inner : InkWell(onTap: onTap, child: inner),
    );

    if (title == null && trailing == null) return box;

    // Der Titel überlappt die Kante zur Hälfte — darum oben Platz freihalten
    // und mit Clip.none nach außen zeichnen lassen.
    //
    // Titel und Beiwert sitzen in einer gemeinsamen Reihe statt in zwei
    // freistehenden Positionen. Nur so kennt der Titel seine verfügbare Breite:
    // ohne Begrenzung wurde ein langer Titel am Kastenrand abgeschnitten und
    // lief vorher unter den Beiwert. Jetzt bricht er um.
    return Padding(
      padding: const EdgeInsets.only(top: _notchHalf),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          box,
          Positioned(
            top: -_notchHalf,
            left: _notchInset,
            right: _notchInset,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (title == null)
                  const SizedBox.shrink()
                else
                  Flexible(
                    child: _Notch(
                      background: p.bg,
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontFamily: Metrics.mono,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: Metrics.trackWider,
                            height: 1.4,
                          ),
                          children: [
                            TextSpan(
                              text: '┤ ',
                              style: TextStyle(color: p.fgFaint),
                            ),
                            TextSpan(
                              text: title!.toUpperCase(),
                              style: TextStyle(color: tone),
                            ),
                            TextSpan(
                              text: ' ├',
                              style: TextStyle(color: p.fgFaint),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (trailing != null)
                  Padding(
                    // Der Beiwert ist eine Spur kleiner gesetzt und sitzt
                    // sonst optisch zu hoch.
                    padding: const EdgeInsets.only(left: 8, top: 1),
                    child: _Notch(
                      background: p.bg,
                      child: Text(
                        trailing!.toUpperCase(),
                        style: TextStyle(
                          fontFamily: Metrics.mono,
                          fontSize: 9.5,
                          letterSpacing: 1.4,
                          height: 1.4,
                          color: p.fgFaint,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Stanzt die Rahmenlinie durch, damit der Titel darin sitzt.
class _Notch extends StatelessWidget {
  const _Notch({required this.child, required this.background});

  final Widget child;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    color: background,
    padding: const EdgeInsets.symmetric(horizontal: 7),
    child: child,
  );
}

/// Versalien-Label mit Haarlinie dahinter — die Abschnittsmarke der Vorlage.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.prefix = '//'});

  final String text;
  final Widget? trailing;

  /// Kommentar-Präfix wie `// STDOUT` in ZENTRALE.
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 11),
      child: Row(
        children: [
          Text(
            prefix == null
                ? text.toUpperCase()
                : '$prefix ${text.toUpperCase()}',
            style: TextStyle(
              fontFamily: Metrics.mono,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: Metrics.trackWider,
              color: p.fgFaint,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: p.border)),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

/// Domänen-Marke. Invertiert statt getönt — wie der aktive Schalter in
/// ZENTRALE (`background: var(--acc); color: var(--bg)`).
class DomainChip extends StatelessWidget {
  const DomainChip(this.domain, {super.key, this.compact = false});

  final String domain;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    final color = AppTheme.domainColor(context, domain);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 7,
        vertical: compact ? 1 : 2,
      ),
      color: color,
      child: Text(
        domain.toUpperCase(),
        style: TextStyle(
          fontFamily: Metrics.mono,
          color: p.onAccent,
          fontSize: compact ? 9 : 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.3,
          height: 1.5,
        ),
      ),
    );
  }
}

/// Balken ohne Rundung, in einer Spur mit Haarlinie.
class ThinProgressBar extends StatelessWidget {
  const ThinProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 5,
  });

  /// 0..1
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    return Container(
      height: height,
      decoration: BoxDecoration(
        border: Border.all(color: p.border, width: Metrics.line),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(color: color),
      ),
    );
  }
}

/// Leerer Zustand — kursiv und zurückgenommen wie `.nodata` in ZENTRALE.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: p.fgFaint),
            const SizedBox(height: 16),
            Text(
              title.toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: Metrics.trackWider,
                color: p.fgDim,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
                height: 1.6,
                color: p.fgFaint,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}
