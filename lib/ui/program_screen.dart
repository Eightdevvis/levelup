import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/resolver.dart';
import '../main.dart';
import '../model/program.dart';
import 'day_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class ProgramScreen extends StatefulWidget {
  const ProgramScreen({super.key, required this.programId});

  final String programId;

  @override
  State<ProgramScreen> createState() => _ProgramScreenState();
}

class _ProgramScreenState extends State<ProgramScreen> {
  int _expandedPhase = 0;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final program = state.library.program(widget.programId);

    if (program == null) {
      return const Scaffold(
        body: Center(child: Text('Programm nicht gefunden.')),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final color = AppTheme.domainColor(program.domain);
    final progress = state.progressFor(program.id);
    final resolver = state.resolver;
    final missing = state.library.missingReferences(program.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(program.name, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => _onMenu(context, value, program),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'export', child: Text('Als JSON kopieren')),
              PopupMenuItem(value: 'reset', child: Text('Fortschritt zurücksetzen')),
              PopupMenuItem(value: 'delete', child: Text('Programm löschen')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          Row(
            children: [
              DomainChip(program.domain),
              const SizedBox(width: 8),
              Text(
                '${program.totalWeeks} Wochen · ${program.totalDays} Tage',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          if (program.description != null) ...[
            const SizedBox(height: 14),
            Text(
              program.description!,
              style: const TextStyle(fontSize: 14.5, height: 1.5),
            ),
          ],
          if (program.rationale != null) ...[
            const SizedBox(height: 16),
            _RationaleCard(text: program.rationale!, color: color),
          ],
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 16),
            _WarningCard(problems: missing),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: color),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(
              state.hasStarted(program.id) ? 'Weitermachen' : 'Programm starten',
            ),
            onPressed: () async {
              await state.startProgram(program.id);
              if (!context.mounted) return;
              final target = state.progressFor(program.id).currentDay;
              _openDay(context, program, target);
            },
          ),
          const SizedBox(height: 8),
          SectionLabel('Phasen'),
          for (var i = 0; i < program.phases.length; i++)
            _PhaseSection(
              program: program,
              phaseIndex: i,
              expanded: _expandedPhase == i,
              color: color,
              resolver: resolver,
              completedDays: progress.completedDays,
              currentDay: progress.currentDay,
              onToggle: () => setState(
                () => _expandedPhase = _expandedPhase == i ? -1 : i,
              ),
              onOpenDay: (globalDay) => _openDay(context, program, globalDay),
            ),
        ],
      ),
    );
  }

  void _openDay(BuildContext context, Program program, int globalDay) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DayScreen(programId: program.id, globalDay: globalDay),
      ),
    );
  }

  Future<void> _onMenu(
    BuildContext context,
    String value,
    Program program,
  ) async {
    final state = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    switch (value) {
      case 'export':
        await Clipboard.setData(
          ClipboardData(text: state.exportProgram(program.id)),
        );
        messenger.showSnackBar(
          const SnackBar(content: Text('JSON in der Zwischenablage.')),
        );
      case 'reset':
        final ok = await _confirm(
          context,
          'Fortschritt zurücksetzen?',
          'Alle abgehakten Tage dieses Programms werden gelöscht.',
        );
        if (ok) await state.resetProgram(program.id);
      case 'delete':
        final ok = await _confirm(
          context,
          'Programm löschen?',
          'Das Programm verschwindet aus der Bibliothek. Übungen bleiben erhalten.',
        );
        if (ok) {
          await state.deleteProgram(program.id);
          navigator.pop();
        }
    }
  }

  Future<bool> _confirm(
    BuildContext context,
    String title,
    String message,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Ja'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

/// Die Begründung des Plans. Bekommt bewusst viel Platz — bei einem
/// AI-generierten Programm ist das der Teil, der erklärt, warum in Woche 1
/// noch kein Bach steht.
class _RationaleCard extends StatelessWidget {
  const _RationaleCard({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                'WARUM DIESER PLAN',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(text, style: const TextStyle(fontSize: 13.5, height: 1.55)),
        ],
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.problems});

  final List<String> problems;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Unvollständiger Import',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: scheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: 8),
          for (final problem in problems.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '• $problem',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onErrorContainer.withValues(alpha: 0.9),
                ),
              ),
            ),
          if (problems.length > 6)
            Text(
              '… und ${problems.length - 6} weitere',
              style: TextStyle(
                fontSize: 12.5,
                color: scheme.onErrorContainer.withValues(alpha: 0.7),
              ),
            ),
        ],
      ),
    );
  }
}

class _PhaseSection extends StatelessWidget {
  const _PhaseSection({
    required this.program,
    required this.phaseIndex,
    required this.expanded,
    required this.color,
    required this.resolver,
    required this.completedDays,
    required this.currentDay,
    required this.onToggle,
    required this.onOpenDay,
  });

  final Program program;
  final int phaseIndex;
  final bool expanded;
  final Color color;
  final ProgramResolver resolver;
  final Set<int> completedDays;
  final int currentDay;
  final VoidCallback onToggle;
  final void Function(int globalDay) onOpenDay;

  @override
  Widget build(BuildContext context) {
    final phase = program.phases[phaseIndex];
    final scheme = Theme.of(context).colorScheme;
    final startDay = resolver.phaseStartDay(program, phaseIndex);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        '${phaseIndex + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            phase.name,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${phase.weeks} Wochen · '
                            '${phase.schedule.cycleLength} Tage/Zyklus',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurface.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      color: scheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
            ),
            if (expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (phase.description != null) ...[
                      Text(
                        phase.description!,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: scheme.onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (phase.goal != null) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.flag_outlined, size: 15, color: color),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              phase.goal!,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontStyle: FontStyle.italic,
                                color: scheme.onSurface.withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],
                    for (var week = 0; week < phase.weeks; week++)
                      _WeekRow(
                        program: program,
                        phaseIndex: phaseIndex,
                        week: week,
                        color: color,
                        resolver: resolver,
                        startDay: startDay + week * phase.schedule.cycleLength,
                        completedDays: completedDays,
                        currentDay: currentDay,
                        onOpenDay: onOpenDay,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Eine Woche als Reihe von Tages-Punkten. Kompakt genug, dass eine ganze
/// Phase auf den Schirm passt.
class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.program,
    required this.phaseIndex,
    required this.week,
    required this.color,
    required this.resolver,
    required this.startDay,
    required this.completedDays,
    required this.currentDay,
    required this.onOpenDay,
  });

  final Program program;
  final int phaseIndex;
  final int week;
  final Color color;
  final ProgramResolver resolver;
  final int startDay;
  final Set<int> completedDays;
  final int currentDay;
  final void Function(int globalDay) onOpenDay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = resolver.resolveWeek(program, phaseIndex, week);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 30,
            child: Text(
              'W${week + 1}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < days.length; i++)
                  _DayDot(
                    day: days[i],
                    globalDay: startDay + i,
                    color: color,
                    isDone: completedDays.contains(startDay + i),
                    isCurrent: currentDay == startDay + i,
                    onTap: () => onOpenDay(startDay + i),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({
    required this.day,
    required this.globalDay,
    required this.color,
    required this.isDone,
    required this.isCurrent,
    required this.onTap,
  });

  final ResolvedDay day;
  final int globalDay;
  final Color color;
  final bool isDone;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final Color background;
    final Color foreground;
    if (day.isRest) {
      background = scheme.onSurface.withValues(alpha: 0.05);
      foreground = scheme.onSurface.withValues(alpha: 0.35);
    } else if (isDone) {
      background = color;
      foreground = Colors.white;
    } else {
      background = color.withValues(alpha: 0.16);
      foreground = color;
    }

    return Tooltip(
      message: day.isRest
          ? 'Pause'
          : '${day.title} · ${day.items.length} Übungen',
      child: GestureDetector(
        onTap: day.isRest ? null : onTap,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(10),
            border: isCurrent
                ? Border.all(color: scheme.onSurface.withValues(alpha: 0.85), width: 2)
                : null,
          ),
          child: day.isRest
              ? Icon(Icons.remove, size: 14, color: foreground)
              : isDone
                  ? Icon(Icons.check, size: 16, color: foreground)
                  : Text(
                      day.title.characters.first.toUpperCase(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: foreground,
                      ),
                    ),
        ),
      ),
    );
  }
}
