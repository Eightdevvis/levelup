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
        appBar: AppBar(title: const Text('FERTIG')),
        body: const EmptyState(
          icon: Icons.check_box_outlined,
          title: 'programm durch',
          message: 'Alle Tage dieses Programms sind abgearbeitet.',
        ),
      );
    }

    final p = AppTheme.paletteOf(context);
    final color = AppTheme.domainColor(context, program.domain);
    final isDone = state.progressFor(programId).isDayComplete(globalDay);
    final onColor = p.onAccent;

    final estimate = day.estimatedSeconds > 0
        ? ' · CA. ${formatDuration(day.estimatedSeconds).toUpperCase()}'
        : '';

    return Scaffold(
      appBar: AppBar(
        title: Text(day.title.toUpperCase()),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: p.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(15, 16, 15, 110),
        children: [
          Text(
            '${day.phase.name.toUpperCase()} · '
            '${day.positionLabel.toUpperCase()}',
            style: TextStyle(
              fontFamily: Metrics.mono,
              fontSize: 10.5,
              letterSpacing: 1.4,
              color: color,
            ),
          ),
          if (day.routine?.description != null) ...[
            const SizedBox(height: 11),
            Text(
              day.routine!.description!,
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 11,
                height: 1.65,
                color: p.fgDim,
              ),
            ),
          ],
          if (day.isRest) ...[
            const SizedBox(height: 50),
            EmptyState(
              icon: Icons.remove,
              title: day.label ?? 'pause',
              message: 'Heute steht nichts an. Erholung ist Teil des Plans.',
            ),
          ] else ...[
            const SizedBox(height: 14),
            Text(
              '// ${day.items.length} ÜBUNGEN$estimate'
              '${isDone ? " · ERLEDIGT" : ""}',
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 10,
                letterSpacing: 1.3,
                color: isDone ? color : p.fgFaint,
              ),
            ),
            const SectionLabel('ablauf'),
            for (var i = 0; i < day.items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _ItemBox(item: day.items[i], index: i, color: color),
              ),
          ],
        ],
      ),
      bottomNavigationBar: day.isRest
          ? null
          : Container(
              decoration: BoxDecoration(
                color: p.bg,
                border: Border(
                  top: BorderSide(color: p.border, width: Metrics.line),
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(15, 12, 15, 14),
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: onColor,
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PlayerScreen(
                          programId: programId,
                          globalDay: globalDay,
                        ),
                      ),
                    ),
                    child: Text(
                      isDone ? 'NOCHMAL DURCHGEHEN' : 'SESSION STARTEN',
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _ItemBox extends StatelessWidget {
  const _ItemBox({
    required this.item,
    required this.index,
    required this.color,
  });

  final ResolvedItem item;
  final int index;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);

    return ZBox(
      title: (index + 1).toString().padLeft(2, '0'),
      trailing: item.slot.optional ? 'optional' : null,
      accent: color,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ExerciseScreen(exercise: item.exercise),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.exercise.name,
            style: TextStyle(
              fontFamily: Metrics.mono,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: p.fg,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 5,
            children: [
              for (final set in item.sets)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: color, width: Metrics.line),
                  ),
                  child: Text(
                    set.describe().toUpperCase(),
                    style: TextStyle(
                      fontFamily: Metrics.mono,
                      fontSize: 10.5,
                      letterSpacing: 0.8,
                      color: color,
                    ),
                  ),
                ),
            ],
          ),
          if (item.slot.note != null) ...[
            const SizedBox(height: 10),
            Text(
              item.slot.note!,
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 10,
                fontStyle: FontStyle.italic,
                height: 1.5,
                color: p.fgFaint,
              ),
            ),
          ],
          if (item.slot.progression.describe() != 'gleichbleibend') ...[
            const SizedBox(height: 9),
            Text(
              '↗ ${item.slot.progression.describe().toUpperCase()}',
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 10,
                letterSpacing: 1.1,
                color: p.fgFaint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
