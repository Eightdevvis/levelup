import 'dart:io';

import 'package:flutter/material.dart';

import '../model/exercise.dart';
import 'theme.dart';
import 'widgets.dart';

/// Das Übungsobjekt in voller Breite: Bild, Anleitung, Vorteile, Hinweise.
///
/// Genau der Teil, den generische Routine-Apps nicht haben — dort ist ein
/// Schritt nur ein Name mit einer Dauer.
class ExerciseScreen extends StatelessWidget {
  const ExerciseScreen({super.key, required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = AppTheme.domainColor(context, exercise.domain);
    final image = exercise.primaryImage;

    return Scaffold(
      appBar: AppBar(
        title: Text(exercise.name, overflow: TextOverflow.ellipsis),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          if (image != null) _MediaBox(media: image),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DomainChip(exercise.domain),
              for (final tag in exercise.tags)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ),
            ],
          ),
          if (exercise.summary != null) ...[
            const SizedBox(height: 16),
            Text(
              exercise.summary!,
              style: const TextStyle(fontSize: 15, height: 1.55),
            ),
          ],
          if (exercise.instructions.isNotEmpty) ...[
            // Nicht "Anleitung" und nicht nummeriert: eine Übung ist EINE
            // Sache, und nummerierte Schritte lasen sich wie eine Liste
            // eigenständiger Aufgaben — genau die Verwechslung, die den
            // Tagesplan unverständlich gemacht hat.
            SectionLabel('ausführung'),
            for (var i = 0; i < exercise.instructions.length; i++)
              _InstructionLine(
                text: exercise.instructions[i],
                color: color,
              ),
          ],
          if (exercise.benefits.isNotEmpty) ...[
            SectionLabel('wofür das gut ist'),
            for (final benefit in exercise.benefits)
              _BulletLine(text: benefit, color: color),
          ],
          if (exercise.cues.isNotEmpty) ...[
            SectionLabel('merksätze'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final cue in exercise.cues)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.zero,
                    ),
                    child: Text(
                      cue,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: color,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (exercise.requirements.isNotEmpty) ...[
            SectionLabel('braucht man'),
            Text(
              exercise.requirements.join(' · '),
              style: TextStyle(
                fontSize: 13.5,
                color: scheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ],
          if (exercise.defaultSets.isNotEmpty) ...[
            SectionLabel('standardansatz'),
            Text(
              exercise.defaultSets.map((s) => s.describe()).join('  ·  '),
              style: TextStyle(
                fontSize: 13.5,
                color: scheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ],
          if (exercise.media.length > 1) ...[
            SectionLabel('weitere medien'),
            for (final media in exercise.media.skip(1))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${media.kind.name}: ${media.uri}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
          ],
          if (exercise.source != null) ...[
            const SizedBox(height: 24),
            Text(
              'Quelle: ${exercise.source}',
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Zeigt lokale Dateien und Assets an. Remote-URLs werden bewusst nur als
/// Verweis dargestellt, damit die App offline nutzbar bleibt und beim Üben
/// nicht auf einen Ladebalken wartet.
class _MediaBox extends StatelessWidget {
  const _MediaBox({required this.media});

  final Media media;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final uri = media.uri;

    Widget content;
    if (uri.startsWith('asset:')) {
      content = Image.asset(
        uri.substring(6),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(scheme, uri),
      );
    } else if (uri.startsWith('file:') || uri.startsWith('/')) {
      final path = uri.startsWith('file:') ? Uri.parse(uri).toFilePath() : uri;
      content = Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(scheme, uri),
      );
    } else {
      content = _placeholder(scheme, uri);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: ClipRRect(
        borderRadius: BorderRadius.zero,
        child: AspectRatio(aspectRatio: 16 / 10, child: content),
      ),
    );
  }

  Widget _placeholder(ColorScheme scheme, String uri) => Container(
    color: scheme.onSurface.withValues(alpha: 0.06),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.image_outlined,
          size: 30,
          color: scheme.onSurface.withValues(alpha: 0.3),
        ),
        const SizedBox(height: 8),
        Text(
          uri,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11.5,
            color: scheme.onSurface.withValues(alpha: 0.45),
          ),
        ),
      ],
    ),
  );
}

class _InstructionLine extends StatelessWidget {
  const _InstructionLine({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ein Strich statt einer Nummer. Nummern machen aus Hinweisen zur
          // Ausführung eine Reihe von Aufgaben, die man einzeln abarbeitet.
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 10),
            child: Text(
              '—',
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 12,
                color: color,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _BulletLine extends StatelessWidget {
  const _BulletLine({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
