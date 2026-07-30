import 'package:flutter/material.dart';

import '../engine/resolver.dart';
import '../main.dart';
import 'exercise_screen.dart';
import 'player_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Die Tagesübersicht: was heute ansteht, bevor man losläuft.
class DayScreen extends StatelessWidget {
  const DayScreen({
    super.key,
    required this.programId,
    required this.globalDay,
  });

  final String programId;
  final int globalDay;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final program = state.library.program(programId);
    if (program == null) {
      return const Scaffold(body: Center(child: Text('Programm fehlt.')));
    }

    final day = state.resolver.resolveDay(program, globalDay);
    if (day == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Fertig')),
        body: const EmptyState(
          icon: Icons.celebration_outlined,
          title: 'Programm durch',
          message: 'Alle Tage dieses Programms sind abgearbeitet.',
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final color = AppTheme.domainColor(program.domain);
    final isDone = state.progressFor(programId).isDayComplete(globalDay);

    return Scaffold(
      appBar: AppBar(title: Text(day.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        children: [
          Text(
            '${day.phase.name} · ${day.positionLabel}',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          if (day.routine?.description != null) ...[
            const SizedBox(height: 10),
            Text(
              day.routine!.description!,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: scheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ],
          if (day.isRest) ...[
            const SizedBox(height: 60),
            EmptyState(
              icon: Icons.nightlight_round,
              title: day.label ?? 'Pause',
              message: 'Heute steht nichts an. Erholung ist Teil des Plans.',
            ),
          ] else ...[
            const SizedBox(height: 16),
            Row(
              children: [
                _Stat(
                  icon: Icons.list_alt_rounded,
                  label: '${day.items.length} Übungen',
                ),
                const SizedBox(width: 16),
                if (day.estimatedSeconds > 0)
                  _Stat(
                    icon: Icons.schedule_rounded,
                    label: 'ca. ${formatDuration(day.estimatedSeconds)}',
                  ),
                if (isDone) ...[
                  const SizedBox(width: 16),
                  _Stat(
                    icon: Icons.check_circle,
                    label: 'erledigt',
                    color: color,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            SectionLabel('Ablauf'),
            for (var i = 0; i < day.items.length; i++)
              _ItemRow(
                item: day.items[i],
                index: i,
                color: color,
              ),
          ],
        ],
      ),
      bottomNavigationBar: day.isRest
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: color),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(isDone ? 'Nochmal durchgehen' : 'Session starten'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlayerScreen(
                        programId: programId,
                        globalDay: globalDay,
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = color ?? scheme.onSurface.withValues(alpha: 0.6);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: tint),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(fontSize: 12.5, color: tint, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.index,
    required this.color,
  });

  final ResolvedItem item;
  final int index;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ExerciseScreen(exercise: item.exercise),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              item.exercise.name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (item.slot.optional) ...[
                            const SizedBox(width: 6),
                            Text(
                              'optional',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface.withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final set in item.sets)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.13),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                set.describe(),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: color,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (item.slot.note != null) ...[
                        const SizedBox(height: 7),
                        Text(
                          item.slot.note!,
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: scheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                      if (item.slot.progression.describe() != 'gleichbleibend') ...[
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            Icon(
                              Icons.trending_up_rounded,
                              size: 13,
                              color: scheme.onSurface.withValues(alpha: 0.45),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              item.slot.progression.describe(),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: scheme.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: scheme.onSurface.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
