import 'package:flutter/material.dart';

import '../main.dart';
import '../model/exercise.dart';
import 'exercise_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Die Übungsdatenbank, durchsuchbar und nach Domäne gruppiert.
///
/// Wächst mit jedem Import: eine Übung, die einmal in der Bibliothek liegt,
/// steht jedem weiteren Programm zur Verfügung.
class ExerciseLibraryScreen extends StatefulWidget {
  const ExerciseLibraryScreen({super.key});

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  String _query = '';
  String? _domainFilter;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final all = state.library.exercises.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final domains = all.map((e) => e.domain).toSet().toList()..sort();

    final query = _query.trim().toLowerCase();
    final filtered = all.where((exercise) {
      if (_domainFilter != null && exercise.domain != _domainFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      return exercise.name.toLowerCase().contains(query) ||
          (exercise.summary ?? '').toLowerCase().contains(query) ||
          exercise.tags.any((t) => t.toLowerCase().contains(query));
    }).toList();

    return Scaffold(
      appBar: AppBar(title: Text('Übungen (${all.length})')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Übung suchen',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
              ),
            ),
          ),
          if (domains.length > 1)
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _FilterPill(
                    label: 'alle',
                    selected: _domainFilter == null,
                    color: Theme.of(context).colorScheme.primary,
                    onTap: () => setState(() => _domainFilter = null),
                  ),
                  for (final domain in domains)
                    _FilterPill(
                      label: domain,
                      selected: _domainFilter == domain,
                      color: AppTheme.domainColor(domain),
                      onTap: () => setState(
                        () => _domainFilter =
                            _domainFilter == domain ? null : domain,
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: filtered.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off,
                    title: 'Nichts gefunden',
                    message: 'Andere Suche oder anderer Filter.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _ExerciseTile(exercise: filtered[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.2)
                : scheme.onSurface.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? color : scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExerciseTile extends StatelessWidget {
  const _ExerciseTile({required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = AppTheme.domainColor(exercise.domain);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ExerciseScreen(exercise: exercise),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 34,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (exercise.summary != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        exercise.summary!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              DomainChip(exercise.domain, compact: true),
            ],
          ),
        ),
      ),
    );
  }
}
