import 'dart:async';

import 'package:flutter/material.dart';

import '../engine/resolver.dart';
import '../main.dart';
import '../model/session.dart';
import '../model/set_spec.dart';
import '../model/target.dart';
import 'exercise_screen.dart';
import 'theme.dart';

/// Ein Schritt der Session: genau ein Satz einer Übung.
class _Step {
  const _Step({required this.itemIndex, required this.setIndex});

  final int itemIndex;
  final int setIndex;
}

/// Der fokussierte Player: eine Sache nach der nächsten, groß genug, um sie
/// vom Notenpult oder von der Matte aus zu lesen.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.programId,
    required this.globalDay,
  });

  final String programId;
  final int globalDay;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final List<_Step> _steps = [];
  final Map<int, Map<int, SetLog>> _logs = {};
  final Set<int> _skippedItems = {};

  int _cursor = 0;
  bool _built = false;
  bool _finished = false;

  Timer? _ticker;
  int _remaining = 0;
  bool _running = false;

  // Zählerstand für Quoten-Ziele im aktuellen Schritt.
  int _correct = 0;
  int _attempts = 0;

  // Ist-Wert für Wiederholungs-Ziele im aktuellen Schritt.
  int? _achievedReps;

  ResolvedDay? _day;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_built) return;

    final state = AppScope.of(context);
    final program = state.library.program(widget.programId);
    if (program == null) return;

    final day = state.resolver.resolveDay(program, widget.globalDay);
    if (day == null) return;

    _day = day;
    for (var i = 0; i < day.items.length; i++) {
      for (var s = 0; s < day.items[i].sets.length; s++) {
        _steps.add(_Step(itemIndex: i, setIndex: s));
      }
    }
    _built = true;
    _prepareStep();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  // -- Schrittwechsel ------------------------------------------------------

  SetSpec? get _currentSet {
    final day = _day;
    if (day == null || _cursor >= _steps.length) return null;
    final step = _steps[_cursor];
    return day.items[step.itemIndex].sets[step.setIndex];
  }

  ResolvedItem? get _currentItem {
    final day = _day;
    if (day == null || _cursor >= _steps.length) return null;
    return day.items[_steps[_cursor].itemIndex];
  }

  void _prepareStep() {
    _ticker?.cancel();
    _running = false;
    _correct = 0;
    _attempts = 0;
    _achievedReps = null;

    final target = _currentSet?.target;
    _remaining = target is DurationTarget ? target.seconds : 0;
  }

  void _goTo(int index) {
    if (index < 0) return;
    if (index >= _steps.length) {
      setState(() => _finished = true);
      _ticker?.cancel();
      return;
    }
    setState(() {
      _cursor = index;
      _prepareStep();
    });
  }

  void _recordAndAdvance({num? achieved}) {
    final step = _steps[_cursor];
    _logs.putIfAbsent(step.itemIndex, () => {});
    _logs[step.itemIndex]![step.setIndex] = SetLog(
      setIndex: step.setIndex,
      done: true,
      achieved: achieved,
    );
    _goTo(_cursor + 1);
  }

  void _skipCurrentExercise() {
    final step = _steps[_cursor];
    _skippedItems.add(step.itemIndex);
    var next = _cursor + 1;
    while (next < _steps.length && _steps[next].itemIndex == step.itemIndex) {
      next++;
    }
    _goTo(next);
  }

  // -- Timer ---------------------------------------------------------------

  void _toggleTimer() {
    if (_running) {
      _ticker?.cancel();
      setState(() => _running = false);
      return;
    }
    setState(() => _running = true);
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_remaining > 0) _remaining--;
        if (_remaining == 0) {
          timer.cancel();
          _running = false;
        }
      });
    });
  }

  // -- Abschluss -----------------------------------------------------------

  Future<void> _finish() async {
    final state = AppScope.of(context);
    final day = _day;
    if (day == null) return;

    final items = <ItemLog>[];
    for (var i = 0; i < day.items.length; i++) {
      final sets = (_logs[i] ?? {}).values.toList()
        ..sort((a, b) => a.setIndex.compareTo(b.setIndex));
      items.add(ItemLog(
        exerciseId: day.items[i].exercise.id,
        sets: sets,
        skipped: _skippedItems.contains(i),
      ));
    }

    await state.completeDay(widget.programId, widget.globalDay, items: items);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  // -- Aufbau --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final day = _day;
    if (day == null) {
      return const Scaffold(body: Center(child: Text('Kein Tag geladen.')));
    }
    if (_steps.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Dieser Tag hat keine Übungen.')),
      );
    }

    final program = AppScope.of(context).library.program(widget.programId);
    final color = AppTheme.domainColor(program?.domain ?? 'allgemein');

    if (_finished) return _buildSummary(context, day, color);

    final item = _currentItem!;
    final set = _currentSet!;
    final step = _steps[_cursor];
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('${_cursor + 1} / ${_steps.length}'),
        actions: [
          IconButton(
            tooltip: 'Übung erklären',
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ExerciseScreen(exercise: item.exercise),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: LinearProgressIndicator(
            value: (_cursor + 1) / _steps.length,
            minHeight: 3,
            backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.sets.length > 1
                    ? 'Satz ${step.setIndex + 1} von ${item.sets.length}'
                    : day.title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: color,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.exercise.name,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  letterSpacing: -0.6,
                ),
              ),
              if (item.exercise.summary != null) ...[
                const SizedBox(height: 10),
                Text(
                  item.exercise.summary!,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
              if (set.note != null || item.slot.note != null) ...[
                const SizedBox(height: 10),
                Text(
                  set.note ?? item.slot.note!,
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: color,
                  ),
                ),
              ],
              Expanded(child: Center(child: _buildTargetArea(set, color))),
              if (item.exercise.cues.isNotEmpty)
                _CueStrip(cues: item.exercise.cues, color: color),
              const SizedBox(height: 12),
              _buildActions(set, color, item),
            ],
          ),
        ),
      ),
    );
  }

  /// Die Mitte des Bildschirms hängt am Übungstyp — das ist die Stelle, an
  /// der sich Domänen-Unabhängigkeit entscheidet.
  Widget _buildTargetArea(SetSpec set, Color color) {
    final scheme = Theme.of(context).colorScheme;
    final target = set.target;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        switch (target) {
          DurationTarget() => _TimerDial(
              remaining: _remaining,
              total: target.seconds,
              color: color,
              running: _running,
              onTap: _toggleTimer,
            ),
          RepsTarget() => _BigValue(
              value: '${_achievedReps ?? target.reps}',
              caption: 'Wiederholungen',
              color: color,
              onAdjust: (delta) => setState(() {
                _achievedReps =
                    ((_achievedReps ?? target.reps) + delta).clamp(0, 999);
              }),
            ),
          QuotaTarget() => _QuotaPad(
              target: target,
              correct: _correct,
              attempts: _attempts,
              color: color,
              onAnswer: (wasCorrect) => setState(() {
                if (_attempts >= target.attempts) return;
                _attempts++;
                if (wasCorrect) _correct++;
              }),
              onUndo: _attempts == 0
                  ? null
                  : () => setState(() {
                        _attempts--;
                        if (_correct > _attempts) _correct = _attempts;
                      }),
            ),
          OpenTarget() => _BigValue(
              value: target.prompt ?? 'offen',
              caption: 'ohne Zielwert',
              color: color,
              small: true,
            ),
        },
        if (set.load != null) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              set.load!.describe(),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActions(SetSpec set, Color color, ResolvedItem item) {
    final target = set.target;
    final quotaReady = target is! QuotaTarget || _attempts > 0;

    return Column(
      children: [
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: color),
          onPressed: quotaReady
              ? () => _recordAndAdvance(
                    achieved: switch (target) {
                      QuotaTarget() => _correct,
                      RepsTarget() => _achievedReps ?? target.reps,
                      _ => null,
                    },
                  )
              : null,
          child: Text(_cursor == _steps.length - 1 ? 'Fertig' : 'Erledigt'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: _cursor == 0 ? null : () => _goTo(_cursor - 1),
                child: const Text('Zurück'),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: _skipCurrentExercise,
                child: Text(
                  item.slot.optional ? 'Überspringen' : 'Übung auslassen',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummary(BuildContext context, ResolvedDay day, Color color) {
    final scheme = Theme.of(context).colorScheme;
    final doneSets = _logs.values.fold<int>(0, (sum, m) => sum + m.length);

    return Scaffold(
      appBar: AppBar(title: const Text('Session')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.check_circle_rounded, size: 48, color: color),
            const SizedBox(height: 16),
            Text(
              day.title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '$doneSets von ${_steps.length} Sätzen abgeschlossen'
              '${_skippedItems.isEmpty ? '' : ' · ${_skippedItems.length} Übung(en) ausgelassen'}',
              style: TextStyle(
                fontSize: 13.5,
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView(
                children: [
                  for (var i = 0; i < day.items.length; i++)
                    _SummaryRow(
                      item: day.items[i],
                      logs: (_logs[i] ?? {}).values.toList(),
                      skipped: _skippedItems.contains(i),
                      color: color,
                    ),
                ],
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: color),
              onPressed: _finish,
              child: const Text('Tag abschließen'),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => setState(() {
                _finished = false;
                _cursor = _steps.length - 1;
                _prepareStep();
              }),
              child: const Text('Zurück zur Session'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bausteine
// ---------------------------------------------------------------------------

class _TimerDial extends StatelessWidget {
  const _TimerDial({
    required this.remaining,
    required this.total,
    required this.color,
    required this.running,
    required this.onTap,
  });

  final int remaining;
  final int total;
  final Color color;
  final bool running;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = total == 0 ? 0.0 : (total - remaining) / total;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 220,
        height: 220,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 220,
              height: 220,
              child: CircularProgressIndicator(
                value: ratio,
                strokeWidth: 8,
                strokeCap: StrokeCap.round,
                backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _clock(remaining),
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w300,
                    fontFeatures: [FontFeature.tabularFigures()],
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  remaining == 0
                      ? 'fertig'
                      : running
                          ? 'tippen zum Pausieren'
                          : 'tippen zum Starten',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _clock(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }
}

class _BigValue extends StatelessWidget {
  const _BigValue({
    required this.value,
    required this.caption,
    required this.color,
    this.onAdjust,
    this.small = false,
  });

  final String value;
  final String caption;
  final Color color;
  final void Function(int delta)? onAdjust;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (onAdjust != null)
              IconButton.filledTonal(
                onPressed: () => onAdjust!(-1),
                icon: const Icon(Icons.remove),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                value,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: small ? 26 : 76,
                  fontWeight: small ? FontWeight.w600 : FontWeight.w300,
                  height: 1.1,
                  letterSpacing: small ? -0.4 : -2,
                  color: small ? scheme.onSurface : color,
                ),
              ),
            ),
            if (onAdjust != null)
              IconButton.filledTonal(
                onPressed: () => onAdjust!(1),
                icon: const Icon(Icons.add),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          caption,
          style: TextStyle(
            fontSize: 12.5,
            color: scheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

/// Trefferzähler — der Modus, den Gehörtraining und Vokabeln brauchen und
/// den kein Workout-Player kann.
class _QuotaPad extends StatelessWidget {
  const _QuotaPad({
    required this.target,
    required this.correct,
    required this.attempts,
    required this.color,
    required this.onAnswer,
    required this.onUndo,
  });

  final QuotaTarget target;
  final int correct;
  final int attempts;
  final Color color;
  final void Function(bool wasCorrect) onAnswer;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final passed = correct >= target.required;
    final remaining = target.attempts - attempts;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$correct',
          style: TextStyle(
            fontSize: 72,
            fontWeight: FontWeight.w300,
            height: 1,
            letterSpacing: -2,
            color: passed ? color : scheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'von ${target.required} nötig · $remaining Versuche übrig',
          style: TextStyle(
            fontSize: 12.5,
            color: scheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _AnswerButton(
              icon: Icons.close_rounded,
              label: 'daneben',
              color: scheme.error,
              onPressed: remaining <= 0 ? null : () => onAnswer(false),
            ),
            const SizedBox(width: 16),
            _AnswerButton(
              icon: Icons.check_rounded,
              label: 'richtig',
              color: color,
              onPressed: remaining <= 0 ? null : () => onAnswer(true),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onUndo,
          child: const Text('rückgängig'),
        ),
      ],
    );
  }
}

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color.withValues(alpha: enabled ? 0.18 : 0.06),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onPressed,
            child: SizedBox(
              width: 84,
              height: 64,
              child: Icon(
                icon,
                size: 30,
                color: color.withValues(alpha: enabled ? 1 : 0.35),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}

class _CueStrip extends StatelessWidget {
  const _CueStrip({required this.cues, required this.color});

  final List<String> cues;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cues.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            cues[index],
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.item,
    required this.logs,
    required this.skipped,
    required this.color,
  });

  final ResolvedItem item;
  final List<SetLog> logs;
  final bool skipped;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = logs.where((l) => l.done).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            skipped
                ? Icons.remove_circle_outline
                : done == item.sets.length
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
            size: 18,
            color: skipped
                ? scheme.onSurface.withValues(alpha: 0.3)
                : done == item.sets.length
                    ? color
                    : scheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.exercise.name,
              style: TextStyle(
                fontSize: 14,
                color: skipped
                    ? scheme.onSurface.withValues(alpha: 0.45)
                    : scheme.onSurface,
              ),
            ),
          ),
          Text(
            skipped ? 'ausgelassen' : '$done/${item.sets.length}',
            style: TextStyle(
              fontSize: 12.5,
              color: scheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}
