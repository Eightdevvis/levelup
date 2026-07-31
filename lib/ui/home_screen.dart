import 'package:flutter/material.dart';

import '../main.dart';
import '../model/program.dart';
import 'exercise_library_screen.dart';
import 'import_screen.dart';
import 'program_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = AppTheme.paletteOf(context);
    final programs = state.programs;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _Header(),
            Expanded(
              child: programs.isEmpty
                  ? EmptyState(
                      icon: Icons.crop_square,
                      title: 'kein programm',
                      message: 'Lass dir von einer AI einen Plan bauen '
                          'und füge ihn hier ein.',
                      action: OutlinedButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ImportScreen(),
                          ),
                        ),
                        child: const Text('PLAN IMPORTIEREN'),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(15, 20, 15, 30),
                      itemCount: programs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 18),
                      itemBuilder: (context, index) =>
                          _ProgramBox(program: programs[index]),
                    ),
            ),
            Container(height: 1, color: p.border),
            _StatusLine(programs: programs),
          ],
        ),
      ),
    );
  }
}

/// Kopf im Stil der Vorlage: Wortmarke mit weiter Sperrung, darunter die
/// Unterzeile, rechts die Werkzeuge — abgeschlossen durch eine Haarlinie.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 14, 10, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: p.border, width: Metrics.line),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LEVELUP',
                  style: TextStyle(
                    fontFamily: Metrics.mono,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 5.5,
                    height: 1,
                    color: p.fg,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'ÜBUNGSPROGRAMME',
                  style: TextStyle(
                    fontFamily: Metrics.mono,
                    fontSize: 8.5,
                    letterSpacing: 4,
                    color: p.fgFaint,
                  ),
                ),
              ],
            ),
          ),
          _ToolButton(
            icon: Icons.grid_view,
            tooltip: 'Übungsbibliothek',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ExerciseLibraryScreen(),
              ),
            ),
          ),
          const SizedBox(width: 7),
          _ToolButton(
            icon: Icons.add,
            tooltip: 'Plan importieren',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ImportScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

/// Eckiger Schalter mit Haarlinie — kein Material-Kreis.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: p.border, width: Metrics.line),
        ),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(icon, size: 15, color: p.fgDim),
          ),
        ),
      ),
    );
  }
}

class _ProgramBox extends StatelessWidget {
  const _ProgramBox({required this.program});

  final Program program;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = AppTheme.paletteOf(context);
    final color = AppTheme.domainColor(context, program.domain);

    final started = state.hasStarted(program.id);
    final progress = state.progressFor(program.id);
    final totalDays = program.totalDays;
    final doneDays = progress.completedDays.length;
    final ratio = totalDays == 0 ? 0.0 : doneDays / totalDays;
    final nextDay = state.resolver.resolveDay(program, progress.currentDay);

    return ZBox(
      title: program.domain,
      trailing: '${program.totalWeeks}W · ${program.phases.length}PH',
      accent: color,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProgramScreen(programId: program.id),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            program.name,
            style: TextStyle(
              fontFamily: Metrics.mono,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              height: 1.35,
              color: p.fg,
            ),
          ),
          if (program.description != null) ...[
            const SizedBox(height: 8),
            Text(
              program.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 10.5,
                height: 1.6,
                color: p.fgDim,
              ),
            ),
          ],
          const SizedBox(height: 15),
          if (started) ...[
            ThinProgressBar(value: ratio, color: color),
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: Text(
                    nextDay == null
                        ? 'ABGESCHLOSSEN'
                        : '→ ${nextDay.title.toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: Metrics.mono,
                      fontSize: 9.5,
                      letterSpacing: 1.2,
                      color: color,
                    ),
                  ),
                ),
                Text(
                  '$doneDays/$totalDays',
                  style: TextStyle(
                    fontFamily: Metrics.mono,
                    fontSize: 9.5,
                    letterSpacing: 1,
                    color: p.fgFaint,
                  ),
                ),
              ],
            ),
          ] else
            Text(
              'NICHT GESTARTET',
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 9.5,
                letterSpacing: 1.6,
                color: p.fgFaint,
              ),
            ),
        ],
      ),
    );
  }
}

/// Fußzeile wie `// STDOUT` — sagt in Kommentarform, was die Bibliothek hält.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.programs});

  final List<Program> programs;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = AppTheme.paletteOf(context);
    final running = programs.where((x) => state.hasStarted(x.id)).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(15, 9, 15, 11),
      child: Text(
        '// ${programs.length} PROGRAMME · $running AKTIV · '
        '${state.library.exercises.length} ÜBUNGEN',
        style: TextStyle(
          fontFamily: Metrics.mono,
          fontSize: 8.5,
          letterSpacing: 1.4,
          color: p.fgFaint,
        ),
      ),
    );
  }
}
