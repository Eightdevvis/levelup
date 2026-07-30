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
    final programs = state.programs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Programme'),
        actions: [
          IconButton(
            tooltip: 'Übungsbibliothek',
            icon: const Icon(Icons.grid_view_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ExerciseLibraryScreen(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Plan importieren',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ImportScreen()),
            ),
          ),
        ],
      ),
      body: programs.isEmpty
          ? EmptyState(
              icon: Icons.auto_awesome_outlined,
              title: 'Noch kein Programm',
              message:
                  'Lass dir von einer AI einen Plan bauen und füge ihn hier ein.',
              action: FilledButton.icon(
                icon: const Icon(Icons.download_outlined),
                label: const Text('Plan importieren'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ImportScreen()),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: programs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) =>
                  _ProgramCard(program: programs[index]),
            ),
    );
  }
}

class _ProgramCard extends StatelessWidget {
  const _ProgramCard({required this.program});

  final Program program;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final color = AppTheme.domainColor(program.domain);

    final started = state.hasStarted(program.id);
    final progress = state.progressFor(program.id);
    final totalDays = program.totalDays;
    final doneDays = progress.completedDays.length;
    final ratio = totalDays == 0 ? 0.0 : doneDays / totalDays;

    final resolver = state.resolver;
    final nextDay = resolver.resolveDay(program, progress.currentDay);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ProgramScreen(programId: program.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  DomainChip(program.domain),
                  const Spacer(),
                  Text(
                    '${program.totalWeeks} Wochen · ${program.phases.length} '
                    '${program.phases.length == 1 ? "Phase" : "Phasen"}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                program.name,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              if (program.description != null) ...[
                const SizedBox(height: 6),
                Text(
                  program.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (started) ...[
                ThinProgressBar(value: ratio, color: color),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.play_circle_outline, size: 16, color: color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        nextDay == null
                            ? 'Programm abgeschlossen'
                            : 'Weiter: ${nextDay.phase.name} · '
                                '${nextDay.positionLabel} · ${nextDay.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: scheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                    Text(
                      '$doneDays/$totalDays',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ] else
                Text(
                  'Noch nicht gestartet',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
