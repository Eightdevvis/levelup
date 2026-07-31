import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/resolver.dart';
import '../main.dart';
import '../model/library.dart';
import '../model/program.dart';
import '../model/session.dart';
import 'day_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class ProgramScreen extends StatefulWidget {
  const ProgramScreen({
    super.key,
    required this.programId,
    this.preview,
    this.allowAdopt = true,
  });

  final String programId;

  /// Ein Plan, der noch NICHT in der Bibliothek des Nutzers liegt.
  ///
  /// Reinschauen und Übernehmen sind zwei verschiedene Dinge. Vorher wurde
  /// beim Antippen in der offenen Bibliothek sofort installiert — wer nur
  /// schauen wollte, hatte das Programm danach auf dem Startbildschirm. Und
  /// weil es der normale Programmbildschirm war, stand dort auch "Programm
  /// löschen", was in einer geteilten Bibliothek nichts zu suchen hat.
  ///
  /// Im Vorschaumodus gibt es deshalb kein Menü, keinen Fortschritt und keinen
  /// Weg in den Player — nur den Knopf, es wirklich zu übernehmen.
  final Bundle? preview;

  /// Ob die Vorschau den Übernehmen-Knopf zeigt.
  ///
  /// Aus der offenen Bibliothek: ja. Aus dem Erzeugen-Bildschirm nein — dort
  /// wird angenommen, und Annehmen ist mehr als Übernehmen (es teilt auch).
  /// Zwei Knöpfe für zwei verschiedene Dinge wären eine Falle.
  final bool allowAdopt;

  bool get isPreview => preview != null;

  @override
  State<ProgramScreen> createState() => _ProgramScreenState();
}

class _ProgramScreenState extends State<ProgramScreen> {
  int _expandedPhase = 0;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final library = widget.preview == null
        ? state.library
        : const Library().merge(widget.preview!);
    final program = library.program(widget.programId);

    if (program == null) {
      return const Scaffold(
        body: Center(child: Text('Programm nicht gefunden.')),
      );
    }

    final p = AppTheme.paletteOf(context);
    final color = AppTheme.domainColor(context, program.domain);
    // In der Vorschau gibt es keinen Fortschritt — das Programm hat nie
    // begonnen und darf auch keinen anfangen.
    final progress = widget.isPreview
        ? ProgramProgress(programId: program.id, startedAt: DateTime.now())
        : state.progressFor(program.id);
    final resolver = ProgramResolver(library);
    final missing = library.missingReferences(program.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(program.name.toUpperCase()),
        actions: [
          // Kein Menü in der Vorschau: nichts hiervon gehört zu einem Plan,
          // der einem noch nicht gehört.
          if (!widget.isPreview)
            PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz, color: p.fgDim),
            onSelected: (value) => _onMenu(context, value, program),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'export', child: Text('Als JSON kopieren')),
              PopupMenuItem(
                value: 'reset',
                child: Text('Fortschritt zurücksetzen'),
              ),
              PopupMenuItem(value: 'delete', child: Text('Programm löschen')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: p.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(15, 16, 15, 40),
        children: [
          Row(
            children: [
              DomainChip(program.domain),
              const SizedBox(width: 9),
              Text(
                '${program.totalWeeks} WOCHEN · ${program.totalDays} TAGE',
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 10.5,
                  letterSpacing: 1.4,
                  color: p.fgFaint,
                ),
              ),
            ],
          ),
          if (program.description != null) ...[
            const SizedBox(height: 14),
            Text(
              program.description!,
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 11.5,
                height: 1.65,
                color: p.fg,
              ),
            ),
          ],
          if (program.rationale != null) ...[
            const SizedBox(height: 20),
            ZBox(
              title: 'warum dieser plan',
              accent: color,
              filled: false,
              child: Text(
                program.rationale!,
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 11,
                  height: 1.7,
                  color: p.fgDim,
                ),
              ),
            ),
          ],
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 18),
            _WarningBox(problems: missing),
          ],
          const SizedBox(height: 22),
          if (widget.isPreview && !widget.allowAdopt)
            const SizedBox.shrink()
          else if (widget.isPreview)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: p.onAccent,
              ),
              onPressed: () => _adopt(context, program),
              child: const Text('IN MEINE BIBLIOTHEK'),
            )
          else
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: p.onAccent,
              ),
              onPressed: () async {
                await state.startProgram(program.id);
                if (!context.mounted) return;
                _openDay(
                  context,
                  program,
                  state.progressFor(program.id).currentDay,
                );
              },
              child: Text(
                state.hasStarted(program.id)
                    ? 'WEITERMACHEN'
                    : 'PROGRAMM STARTEN',
              ),
            ),
          const SectionLabel('phasen'),
          for (var i = 0; i < program.phases.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _PhaseBox(
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
                // In der Vorschau führt kein Tag in den Player: der greift
                // auf die Bibliothek des Nutzers zu, in der es das Programm
                // noch gar nicht gibt.
                onOpenDay: widget.isPreview
                    ? null
                    : (globalDay) => _openDay(context, program, globalDay),
              ),
            ),
        ],
      ),
    );
  }

  /// Übernehmen ist der einzige Weg, wie ein Plan aus der Vorschau in die
  /// eigene Bibliothek kommt — bewusst ein Knopfdruck, nicht ein Blick.
  Future<void> _adopt(BuildContext context, Program program) async {
    final state = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    await state.installBundle(widget.preview!);
    if (!context.mounted) return;

    messenger.showSnackBar(
      SnackBar(content: Text('// ${program.name.toUpperCase()} ÜBERNOMMEN')),
    );
    // Ersetzen statt draufsetzen: der Zurück-Weg soll nicht in eine Vorschau
    // führen, die es so nicht mehr gibt.
    navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ProgramScreen(programId: program.id),
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
          const SnackBar(content: Text('// JSON IN DER ZWISCHENABLAGE')),
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
          'Das Programm verschwindet aus der Bibliothek. '
              'Übungen bleiben erhalten.',
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
        title: Text(title.toUpperCase()),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ABBRECHEN'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('JA'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

class _WarningBox extends StatelessWidget {
  const _WarningBox({required this.problems});

  final List<String> problems;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    return ZBox(
      title: 'unvollständiger import',
      accent: p.error,
      filled: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final problem in problems.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '· $problem',
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 10.5,
                  height: 1.5,
                  color: p.error,
                ),
              ),
            ),
          if (problems.length > 6)
            Text(
              '… und ${problems.length - 6} weitere',
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 10.5,
                fontStyle: FontStyle.italic,
                color: p.fgFaint,
              ),
            ),
        ],
      ),
    );
  }
}

class _PhaseBox extends StatelessWidget {
  const _PhaseBox({
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
  /// Null in der Vorschau — dort führt kein Tag irgendwohin.
  final void Function(int globalDay)? onOpenDay;

  @override
  Widget build(BuildContext context) {
    final phase = program.phases[phaseIndex];
    final p = AppTheme.paletteOf(context);
    final startDay = resolver.phaseStartDay(program, phaseIndex);

    return ZBox(
      // Der ganze Kasten schaltet um. Vorher tat das nur die Zeile
      // "[ + WOCHEN ZEIGEN ]" ganz unten — man musste einen Fadenstrich
      // treffen, um eine Phase aufzuklappen, und der Kasten selbst reagierte
      // auf nichts.
      onTap: onToggle,
      // In der Kerbe steht nur die Nummer. Der Name kann ein ganzer Satz sein
      // ("Woche 3: Genauigkeit und echter Text") und gehört damit in den
      // Kasten, wo er die volle Breite hat, statt in ein Etikett.
      title: 'phase ${phaseIndex + 1}',
      trailing: '${phase.weeks}W',
      accent: color,
      padding: const EdgeInsets.fromLTRB(13, 20, 13, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            phase.name,
            style: TextStyle(
              fontFamily: Metrics.display,
              fontSize: 21,
              height: 1.15,
              color: p.fg,
            ),
          ),
          const SizedBox(height: 11),
          if (phase.description != null && expanded) ...[
            Text(
              phase.description!,
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 10.5,
                height: 1.65,
                color: p.fgDim,
              ),
            ),
            const SizedBox(height: 11),
          ],
          if (phase.goal != null && expanded) ...[
            Text(
              '→ ${phase.goal}',
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 10.5,
                fontStyle: FontStyle.italic,
                height: 1.5,
                color: color,
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (expanded)
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
              )
          else
            Text(
              '${phase.weeks} WOCHEN · ${phase.schedule.cycleLength} TAGE/ZYKLUS',
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 10.5,
                letterSpacing: 1.2,
                color: p.fgFaint,
              ),
            ),
          const SizedBox(height: 10),
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                expanded ? '[ − ZUKLAPPEN ]' : '[ + WOCHEN ZEIGEN ]',
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 10.5,
                  letterSpacing: 1.2,
                  color: p.fgDim,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Eine Woche als Reihe quadratischer Tagesfelder.
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
  /// Null in der Vorschau — dort führt kein Tag irgendwohin.
  final void Function(int globalDay)? onOpenDay;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    final days = resolver.resolveWeek(program, phaseIndex, week);

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              'W${week + 1}',
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 10,
                letterSpacing: 0.8,
                color: p.fgFaint,
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (var i = 0; i < days.length; i++)
                  _DaySquare(
                    day: days[i],
                    color: color,
                    isDone: completedDays.contains(startDay + i),
                    isCurrent: currentDay == startDay + i,
                    onTap: onOpenDay == null
                        ? null
                        : () => onOpenDay!(startDay + i),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DaySquare extends StatelessWidget {
  const _DaySquare({
    required this.day,
    required this.color,
    required this.isDone,
    required this.isCurrent,
    required this.onTap,
  });

  final ResolvedDay day;
  final Color color;
  final bool isDone;
  final bool isCurrent;
  /// Null, wenn der Tag nirgendwohin führt — Pausentag oder Vorschau.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    final onColor = p.onAccent;

    late final Color background;
    late final Color foreground;
    late final Color line;

    if (day.isRest) {
      background = Colors.transparent;
      foreground = p.fgFaint;
      line = p.border;
    } else if (isDone) {
      // Erledigt wird invertiert dargestellt — wie der aktive Schalter.
      background = color;
      foreground = onColor;
      line = color;
    } else {
      background = Colors.transparent;
      foreground = color;
      line = color.withValues(alpha: 0.55);
    }

    return Tooltip(
      message: day.isRest
          ? 'Pause'
          : '${day.title} · ${day.items.length} Übungen',
      child: GestureDetector(
        onTap: day.isRest ? null : onTap,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            border: Border.all(
              color: isCurrent ? p.fg : line,
              width: isCurrent ? 2 : Metrics.line,
            ),
          ),
          child: Text(
            day.isRest ? '·' : day.title.characters.first.toUpperCase(),
            style: TextStyle(
              fontFamily: Metrics.mono,
              fontSize: day.isRest ? 13 : 11,
              fontWeight: FontWeight.w700,
              color: foreground,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
