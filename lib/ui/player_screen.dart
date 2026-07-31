import 'dart:async';

import 'package:flutter/material.dart';

import '../engine/resolver.dart';
import '../main.dart';
import '../model/session.dart';
import '../model/set_spec.dart';
import '../model/target.dart';
import 'exercise_screen.dart';
import 'theme.dart';
import 'widgets.dart';

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

  int _correct = 0;
  int _attempts = 0;
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
      items.add(
        ItemLog(
          exerciseId: day.items[i].exercise.id,
          sets: sets,
          skipped: _skippedItems.contains(i),
        ),
      );
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

    final p = AppTheme.paletteOf(context);
    final program = AppScope.of(context).library.program(widget.programId);
    final color = AppTheme.domainColor(context, program?.domain ?? 'allgemein');

    if (_finished) return _buildSummary(context, day, color);

    final item = _currentItem!;
    final set = _currentSet!;
    final step = _steps[_cursor];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${(_cursor + 1).toString().padLeft(2, '0')} / '
          '${_steps.length.toString().padLeft(2, '0')}',
        ),
        actions: [
          IconButton(
            tooltip: 'Übung erklären',
            icon: Icon(Icons.info_outline, color: p.fgDim),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ExerciseScreen(exercise: item.exercise),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(5),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 0, 15, 3),
            child: ThinProgressBar(
              value: (_cursor + 1) / _steps.length,
              color: color,
              height: 4,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 14, 15, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Wo man steht. Das Einzige neben der Übung selbst, das oben
              // stehen darf.
              Text(
                'ÜBUNG ${step.itemIndex + 1} VON ${day.items.length}'
                '${item.sets.length > 1 ? " · SATZ ${step.setIndex + 1}/${item.sets.length}" : ""}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 10.5,
                  letterSpacing: 1.6,
                  color: p.fgDim,
                ),
              ),

              // Das Bild trägt die Fläche. Gibt es keins, bleibt sie leer —
              // besser als sie mit Erklärtext zu füllen, den man während der
              // Ausführung nicht liest.
              Expanded(
                child: Center(
                  child: ExerciseThumb(exercise: item.exercise, size: 240),
                ),
              ),

              // Titel unten mittig, groß und fett — wie in einer Fitness-App.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(
                      item.exercise.name,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: Metrics.mono,
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        color: p.fg,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Das Fragezeichen am Titel: alles Erklärende liegt
                  // dahinter, nicht auf dem Bildschirm.
                  InkWell(
                    onTap: () => _explain(context, item),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: p.fgDim, width: Metrics.line),
                        ),
                        child: Text(
                          '?',
                          style: TextStyle(
                            fontFamily: Metrics.mono,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: p.fgDim,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),
              Text(
                set.describe().toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 11,
                  letterSpacing: 1.4,
                  color: p.fgDim,
                ),
              ),

              // Nur die Dauer braucht ein Bedienelement — eine Zeit läuft,
              // ob man hinschaut oder nicht. Alles andere hakt man ab.
              if (set.target is DurationTarget) ...[
                const SizedBox(height: 14),
                _buildTargetArea(set, color),
              ],

              const SizedBox(height: 16),
              _buildActions(set, color, item),
            ],
          ),
        ),
      ),
    );
  }

  /// Was die Übung ist und wofür sie gut ist — hinter dem Fragezeichen.
  ///
  /// Während der Ausführung liest das niemand; davor oder bei Unsicherheit
  /// schon. Deshalb erreichbar, aber nicht sichtbar.
  Future<void> _explain(BuildContext context, ResolvedItem item) {
    final p = AppTheme.paletteOf(context);
    final ex = item.exercise;

    Widget absatz(String text, {bool kursiv = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: Metrics.mono,
          fontSize: 11.5,
          height: 1.65,
          fontStyle: kursiv ? FontStyle.italic : FontStyle.normal,
          color: p.fgDim,
        ),
      ),
    );

    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 56),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 14, 15, 4),
              child: Text(
                ex.name.toUpperCase(),
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: Metrics.trackWider,
                  height: 1.4,
                  color: p.fg,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(15, 10, 15, 10),
                children: [
                  if (ex.summary != null) absatz(ex.summary!),
                  for (final line in ex.instructions) absatz('— $line'),
                  if (ex.benefits.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    for (final line in ex.benefits) absatz('↗ $line'),
                  ],
                  for (final line in ex.cues) absatz(line, kursiv: true),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 0, 15, 12),
              child: TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('SCHLIESSEN'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Die Mitte des Bildschirms hängt am Übungstyp — das ist die Stelle, an
  /// der sich Domänen-Unabhängigkeit entscheidet.
  Widget _buildTargetArea(SetSpec set, Color color) {
    final p = AppTheme.paletteOf(context);
    final target = set.target;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        switch (target) {
          DurationTarget() => _TimerPanel(
            remaining: _remaining,
            total: target.seconds,
            color: color,
            running: _running,
            onTap: _toggleTimer,
          ),
          RepsTarget() => _CounterPanel(
            value: _achievedReps ?? target.reps,
            color: color,
            onAdjust: (delta) => setState(() {
              _achievedReps = ((_achievedReps ?? target.reps) + delta).clamp(
                0,
                999,
              );
            }),
          ),
          QuotaTarget() => _QuotaPanel(
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
          OpenTarget() => _OpenPanel(prompt: target.prompt),
        },
        if (set.load != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              border: Border.all(color: p.border, width: Metrics.line),
            ),
            child: Text(
              set.load!.describe().toUpperCase(),
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: p.fg,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActions(SetSpec set, Color color, ResolvedItem item) {
    final p = AppTheme.paletteOf(context);
    final target = set.target;
    final onColor = p.onAccent;

    return Column(
      children: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: onColor,
          ),
          // Früher war "Erledigt" bei Quoten gesperrt, bis jemand am
          // Trefferzähler geklickt hatte. Den Zähler gibt es nicht mehr — er
          // stand groß in der Mitte und beantwortete eine Frage, die niemand
          // gestellt hatte. Ohne ihn muss der Knopf offen sein, sonst ließe
          // sich eine Quoten-Übung überhaupt nicht abschließen.
          onPressed: () => _recordAndAdvance(
            achieved: switch (target) {
              QuotaTarget() => _correct > 0 ? _correct : null,
              RepsTarget() => _achievedReps ?? target.reps,
              _ => null,
            },
          ),
          child: Text(_cursor == _steps.length - 1 ? 'FERTIG' : 'ERLEDIGT'),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: _cursor == 0 ? null : () => _goTo(_cursor - 1),
                child: const Text('← ZURÜCK'),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: _skipCurrentExercise,
                child: Text(item.slot.optional ? 'ÜBERSPRINGEN' : 'AUSLASSEN'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummary(BuildContext context, ResolvedDay day, Color color) {
    final p = AppTheme.paletteOf(context);
    final doneSets = _logs.values.fold<int>(0, (sum, m) => sum + m.length);
    final onColor = p.onAccent;
    final skipped = _skippedItems.isEmpty
        ? ''
        : ' · ${_skippedItems.length} AUSGELASSEN';

    return Scaffold(
      appBar: AppBar(title: const Text('SESSION')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(15, 12, 15, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              day.title.toUpperCase(),
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: p.fg,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '// $doneSets VON ${_steps.length} SÄTZEN$skipped',
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 10.5,
                letterSpacing: 1.3,
                color: p.fgFaint,
              ),
            ),
            const SizedBox(height: 18),
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
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: onColor,
              ),
              onPressed: _finish,
              child: const Text('TAG ABSCHLIESSEN'),
            ),
            TextButton(
              onPressed: () => setState(() {
                _finished = false;
                _cursor = _steps.length - 1;
                _prepareStep();
              }),
              child: const Text('← ZURÜCK ZUR SESSION'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Anzeigen — Ziffern in VT323, wie die Displays in ZENTRALE
// ---------------------------------------------------------------------------

class _TimerPanel extends StatelessWidget {
  const _TimerPanel({
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
    final p = AppTheme.paletteOf(context);
    final ratio = total == 0 ? 0.0 : (total - remaining) / total;

    return GestureDetector(
      onTap: onTap,
      child: ZBox(
        title: running ? 'läuft' : 'timer',
        trailing: formatDuration(total),
        accent: color,
        filled: false,
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 15),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _clock(remaining),
              style: TextStyle(
                fontFamily: Metrics.display,
                fontSize: 84,
                height: 0.9,
                letterSpacing: 2,
                color: remaining == 0 ? p.fgFaint : color,
              ),
            ),
            const SizedBox(height: 12),
            ThinProgressBar(value: ratio, color: color, height: 6),
            const SizedBox(height: 11),
            Text(
              remaining == 0
                  ? 'ABGELAUFEN'
                  : running
                  ? 'TIPPEN ZUM PAUSIEREN'
                  : 'TIPPEN ZUM STARTEN',
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 10,
                letterSpacing: 1.5,
                color: p.fgFaint,
              ),
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

class _CounterPanel extends StatelessWidget {
  const _CounterPanel({
    required this.value,
    required this.color,
    required this.onAdjust,
  });

  final int value;
  final Color color;
  final void Function(int delta) onAdjust;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);

    return ZBox(
      title: 'wiederholungen',
      accent: color,
      filled: false,
      padding: const EdgeInsets.fromLTRB(14, 22, 14, 15),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SquareButton(label: '−', onTap: () => onAdjust(-1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '$value',
                  style: TextStyle(
                    fontFamily: Metrics.display,
                    fontSize: 84,
                    height: 0.9,
                    color: color,
                  ),
                ),
              ),
              _SquareButton(label: '+', onTap: () => onAdjust(1)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'ANPASSEN, WENN ES ABWICH',
            style: TextStyle(
              fontFamily: Metrics.mono,
              fontSize: 10,
              letterSpacing: 1.3,
              color: p.fgFaint,
            ),
          ),
        ],
      ),
    );
  }
}

/// Trefferzähler — der Modus, den Gehörtraining und Vokabeln brauchen und
/// den kein Workout-Player kann.
class _QuotaPanel extends StatelessWidget {
  const _QuotaPanel({
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
    final p = AppTheme.paletteOf(context);
    final passed = correct >= target.required;
    final remaining = target.attempts - attempts;

    return ZBox(
      title: 'treffer',
      trailing: '${target.required}/${target.attempts}',
      accent: color,
      filled: false,
      padding: const EdgeInsets.fromLTRB(14, 22, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$correct',
                style: TextStyle(
                  fontFamily: Metrics.display,
                  fontSize: 84,
                  height: 0.9,
                  color: passed ? color : p.fg,
                ),
              ),
              Text(
                '/${target.required}',
                style: TextStyle(
                  fontFamily: Metrics.display,
                  fontSize: 40,
                  height: 1.75,
                  color: p.fgFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$remaining VERSUCHE ÜBRIG',
            style: TextStyle(
              fontFamily: Metrics.mono,
              fontSize: 10,
              letterSpacing: 1.4,
              color: p.fgFaint,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _AnswerButton(
                label: 'DANEBEN',
                tone: p.error,
                onPressed: remaining <= 0 ? null : () => onAnswer(false),
              ),
              const SizedBox(width: 10),
              _AnswerButton(
                label: 'RICHTIG',
                tone: color,
                onPressed: remaining <= 0 ? null : () => onAnswer(true),
              ),
            ],
          ),
          TextButton(onPressed: onUndo, child: const Text('RÜCKGÄNGIG')),
        ],
      ),
    );
  }
}

/// Aufgabe ohne Zielwert — bewusst ohne erfundene Zahl.
class _OpenPanel extends StatelessWidget {
  const _OpenPanel({this.prompt});

  final String? prompt;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    return ZBox(
      title: 'offene aufgabe',
      filled: false,
      padding: const EdgeInsets.fromLTRB(18, 26, 18, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            (prompt ?? 'offen').toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: Metrics.mono,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              height: 1.5,
              color: p.fg,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'KEIN ZIELWERT — NUR ERLEDIGT',
            style: TextStyle(
              fontFamily: Metrics.mono,
              fontSize: 10,
              letterSpacing: 1.4,
              color: p.fgFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: p.border, width: Metrics.line),
      ),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 16,
                color: p.fgDim,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    required this.label,
    required this.tone,
    required this.onPressed,
  });

  final String label;
  final Color tone;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    final enabled = onPressed != null;
    final onTone = p.onAccent;

    return Material(
      color: enabled ? tone : Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: enabled ? tone : p.border, width: Metrics.line),
      ),
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 100,
          height: 44,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: enabled ? onTone : p.fgFaint,
              ),
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
    final p = AppTheme.paletteOf(context);
    final done = logs.where((l) => l.done).length;
    final complete = done == item.sets.length && !skipped;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: p.border, width: Metrics.line),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              skipped ? '·' : (complete ? '×' : '○'),
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: skipped ? p.fgFaint : (complete ? color : p.fgDim),
              ),
            ),
          ),
          Expanded(
            child: Text(
              item.exercise.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 11.5,
                color: skipped ? p.fgFaint : p.fg,
              ),
            ),
          ),
          Text(
            skipped ? 'AUSGELASSEN' : '$done/${item.sets.length}',
            style: TextStyle(
              fontFamily: Metrics.mono,
              fontSize: 10.5,
              letterSpacing: 1.1,
              color: p.fgFaint,
            ),
          ),
        ],
      ),
    );
  }
}
