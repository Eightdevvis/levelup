import 'exercise.dart';
import 'library.dart';
import 'program.dart';
import 'progression.dart';
import 'set_spec.dart';

/// Eine Änderung an einem bestehenden Plan.
///
/// Warum ein Patch und kein neuer Plan: einen Plan wegen "die eine Übung passt
/// nicht" komplett neu schreiben zu lassen wäre teuer und langsam — vor allem
/// aber würde es alles andere mit umformulieren, womit der Nutzer zufrieden
/// war. Ein Patch ändert, was gemeint war, und lässt den Rest buchstäblich
/// unangetastet.
sealed class PatchOp {
  const PatchOp();

  static PatchOp? fromJson(Map<String, dynamic> json) {
    String? str(String key) {
      final value = json[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    return switch (json['op']) {
      'replaceExercise' => switch ((
        str('oldExerciseId'),
        str('newExerciseId'),
      )) {
        (final String from, final String to) => ReplaceExercise(
          from: from,
          to: to,
          routineId: str('routineId'),
        ),
        _ => null,
      },
      'removeExercise' => switch (str('exerciseId')) {
        final String id => RemoveExercise(
          exerciseId: id,
          routineId: str('routineId'),
        ),
        _ => null,
      },
      'addExercise' => switch ((str('routineId'), json['slot'])) {
        (final String routineId, final Map<String, dynamic> slot) =>
          AddExercise(
            routineId: routineId,
            slot: ExerciseSlot.fromJson(slot),
          ),
        _ => null,
      },
      'setSets' => switch ((str('routineId'), str('exerciseId'))) {
        (final String routineId, final String exerciseId) => SetSets(
          routineId: routineId,
          exerciseId: exerciseId,
          sets: (json['sets'] as List<dynamic>? ?? const [])
              .map((e) => SetSpec.fromJson(e as Map<String, dynamic>))
              .toList(growable: false),
        ),
        _ => null,
      },
      'setProgression' => switch ((
        str('routineId'),
        str('exerciseId'),
        json['progression'],
      )) {
        (
          final String routineId,
          final String exerciseId,
          final Map<String, dynamic> progression,
        ) =>
          SetProgressionOp(
            routineId: routineId,
            exerciseId: exerciseId,
            progression: Progression.fromJson(progression),
          ),
        _ => null,
      },
      'setPhaseWeeks' => switch ((str('phaseId'), json['weeks'])) {
        (final String phaseId, final num weeks) when weeks >= 1 =>
          SetPhaseWeeks(phaseId: phaseId, weeks: weeks.round()),
        _ => null,
      },
      'setProgramText' => switch ((str('field'), str('text'))) {
        (final String field, final String text)
            when _programFields.contains(field) =>
          SetProgramText(field: field, text: text),
        _ => null,
      },
      'setPhaseText' => switch ((str('phaseId'), str('field'), str('text'))) {
        (final String phaseId, final String field, final String text)
            when _phaseFields.contains(field) =>
          SetPhaseText(phaseId: phaseId, field: field, text: text),
        _ => null,
      },
      _ => null,
    };
  }

  static const _programFields = {'name', 'description', 'rationale'};
  static const _phaseFields = {'name', 'description', 'goal'};

  /// Kurz und in Alltagssprache — die App zeigt das als Änderungsliste.
  String describe();
}

class ReplaceExercise extends PatchOp {
  const ReplaceExercise({required this.from, required this.to, this.routineId});

  final String from;
  final String to;

  /// Ohne Angabe gilt die Änderung für alle Listen.
  final String? routineId;

  @override
  String describe() => '$from → $to';
}

class RemoveExercise extends PatchOp {
  const RemoveExercise({required this.exerciseId, this.routineId});

  final String exerciseId;
  final String? routineId;

  @override
  String describe() => '$exerciseId entfernt';
}

class AddExercise extends PatchOp {
  const AddExercise({required this.routineId, required this.slot});

  final String routineId;
  final ExerciseSlot slot;

  @override
  String describe() => '${slot.exerciseId} ergänzt';
}

class SetSets extends PatchOp {
  const SetSets({
    required this.routineId,
    required this.exerciseId,
    required this.sets,
  });

  final String routineId;
  final String exerciseId;
  final List<SetSpec> sets;

  @override
  String describe() => '$exerciseId: Sätze geändert';
}

class SetProgressionOp extends PatchOp {
  const SetProgressionOp({
    required this.routineId,
    required this.exerciseId,
    required this.progression,
  });

  final String routineId;
  final String exerciseId;
  final Progression progression;

  @override
  String describe() => '$exerciseId: Steigerung geändert';
}

class SetPhaseWeeks extends PatchOp {
  const SetPhaseWeeks({required this.phaseId, required this.weeks});

  final String phaseId;
  final int weeks;

  @override
  String describe() => '$phaseId: $weeks Wochen';
}

class SetProgramText extends PatchOp {
  const SetProgramText({required this.field, required this.text});

  final String field;
  final String text;

  @override
  String describe() => 'Programm: $field neu';
}

class SetPhaseText extends PatchOp {
  const SetPhaseText({
    required this.phaseId,
    required this.field,
    required this.text,
  });

  final String phaseId;
  final String field;
  final String text;

  @override
  String describe() => '$phaseId: $field neu';
}

/// Das Ergebnis einer Überarbeitung: neue Bausteine plus die Änderungen.
class PlanPatch {
  const PlanPatch({
    this.exercises = const [],
    this.operations = const [],
    this.personalNote,
  });

  /// Bausteine, die es vorher nicht gab und die die Operationen brauchen.
  final List<Exercise> exercises;
  final List<PatchOp> operations;

  /// Was geändert wurde und warum, an den Nutzer gerichtet.
  final String? personalNote;

  bool get isEmpty => operations.isEmpty;

  static PlanPatch fromJson(Map<String, dynamic> json) {
    final note = json['personalNote'];
    final ops = <PatchOp>[];
    for (final raw in json['operations'] as List<dynamic>? ?? const []) {
      if (raw is! Map<String, dynamic>) continue;
      // Eine unlesbare Operation wird übersprungen, nicht zum Fehler erhoben:
      // die anderen sind deshalb nicht falsch.
      final op = PatchOp.fromJson(raw);
      if (op != null) ops.add(op);
    }

    return PlanPatch(
      exercises: (json['exercises'] as List<dynamic>? ?? const [])
          .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      operations: ops,
      personalNote: note is String && note.trim().isNotEmpty
          ? note.trim()
          : null,
    );
  }
}

/// Das Ergebnis des Anwendens — inklusive dem, was nicht ging.
class PatchResult {
  const PatchResult({required this.bundle, this.skipped = const []});

  final Bundle bundle;

  /// Operationen, die ins Leere zeigten. Werden dem Nutzer gezeigt, statt sie
  /// stillschweigend zu schlucken: er soll sehen, was NICHT passiert ist.
  final List<String> skipped;
}

/// Wendet einen Patch auf ein Plan-Bundle an.
///
/// Rein funktional — das Original bleibt unangetastet, damit die Oberfläche
/// vorher und nachher nebeneinander halten kann.
PatchResult applyPatch(Bundle bundle, PlanPatch patch) {
  final skipped = <String>[];

  // Neue Bausteine dazu, gleiche Kennung ersetzt die alte Fassung.
  final exercises = <String, Exercise>{
    for (final e in bundle.exercises) e.id: e,
    for (final e in patch.exercises) e.id: e,
  };

  var routines = [...bundle.routines];
  var programs = [...bundle.programs];

  bool touchesRoutine(String? only, Routine routine) =>
      only == null || only == routine.id;

  for (final op in patch.operations) {
    switch (op) {
      case ReplaceExercise(:final from, :final to, :final routineId):
        if (!exercises.containsKey(to)) {
          skipped.add('${op.describe()} — "$to" fehlt im Patch');
          break;
        }
        // Gezählt wird der Verschwundene, nicht der Neue: "to" könnte schon
        // anderswo im Plan stehen und würde einen Treffer vortäuschen.
        final before = _countSlots(routines, from);
        routines = [
          for (final routine in routines)
            if (!touchesRoutine(routineId, routine))
              routine
            else
              _withSlots(routine, [
                for (final slot in routine.slots)
                  if (slot.exerciseId != from)
                    slot
                  else
                    _slotWith(slot, exerciseId: to),
              ]),
        ];
        if (_countSlots(routines, from) == before) {
          skipped.add('${op.describe()} — "$from" nicht gefunden');
        }

      case RemoveExercise(:final exerciseId, :final routineId):
        final before = _countSlots(routines, exerciseId);
        routines = [
          for (final routine in routines)
            if (!touchesRoutine(routineId, routine))
              routine
            else
              _withSlots(routine, [
                for (final slot in routine.slots)
                  if (slot.exerciseId != exerciseId) slot,
              ]),
        ];
        if (_countSlots(routines, exerciseId) == before) {
          skipped.add('${op.describe()} — nicht gefunden');
        }

      case AddExercise(:final routineId, :final slot):
        if (!exercises.containsKey(slot.exerciseId)) {
          skipped.add('${op.describe()} — Baustein fehlt im Patch');
          break;
        }
        final index = routines.indexWhere((r) => r.id == routineId);
        if (index == -1) {
          skipped.add('${op.describe()} — Liste "$routineId" fehlt');
          break;
        }
        routines[index] = _withSlots(routines[index], [
          ...routines[index].slots,
          slot,
        ]);

      case SetSets(:final routineId, :final exerciseId, :final sets):
        if (!_editSlot(routines, routineId, exerciseId, (s) => _slotWith(s, sets: sets))) {
          skipped.add('${op.describe()} — nicht gefunden');
        }

      case SetProgressionOp(
        :final routineId,
        :final exerciseId,
        :final progression,
      ):
        if (!_editSlot(
          routines,
          routineId,
          exerciseId,
          (s) => _slotWith(s, progression: progression),
        )) {
          skipped.add('${op.describe()} — nicht gefunden');
        }

      case SetPhaseWeeks(:final phaseId, :final weeks):
        if (!_editPhase(programs, phaseId, (p) => _phaseWith(p, weeks: weeks))) {
          skipped.add('${op.describe()} — Phase fehlt');
        }

      case SetPhaseText(:final phaseId, :final field, :final text):
        if (!_editPhase(
          programs,
          phaseId,
          (p) => switch (field) {
            'name' => _phaseWith(p, name: text),
            'description' => _phaseWith(p, description: text),
            _ => _phaseWith(p, goal: text),
          },
        )) {
          skipped.add('${op.describe()} — Phase fehlt');
        }

      case SetProgramText(:final field, :final text):
        if (programs.isEmpty) {
          skipped.add('${op.describe()} — kein Programm');
          break;
        }
        programs[0] = switch (field) {
          'name' => _programWith(programs[0], name: text),
          'description' => _programWith(programs[0], description: text),
          _ => _programWith(programs[0], rationale: text),
        };
    }
  }

  // Bausteine, die nach den Änderungen niemand mehr braucht, fliegen raus —
  // sonst wächst die Bibliothek mit Karteileichen zu.
  final used = <String>{
    for (final routine in routines)
      for (final slot in routine.slots) slot.exerciseId,
  };

  return PatchResult(
    bundle: Bundle(
      version: bundle.version,
      personalNote: patch.personalNote ?? bundle.personalNote,
      exercises: [
        for (final entry in exercises.entries)
          if (used.contains(entry.key)) entry.value,
      ],
      routines: routines,
      programs: programs,
    ),
    skipped: skipped,
  );
}

int _countSlots(List<Routine> routines, String exerciseId) => routines.fold(
  0,
  (sum, r) => sum + r.slots.where((s) => s.exerciseId == exerciseId).length,
);

bool _editSlot(
  List<Routine> routines,
  String routineId,
  String exerciseId,
  ExerciseSlot Function(ExerciseSlot) edit,
) {
  final index = routines.indexWhere((r) => r.id == routineId);
  if (index == -1) return false;

  final slots = [...routines[index].slots];
  var hit = false;
  for (var i = 0; i < slots.length; i++) {
    if (slots[i].exerciseId != exerciseId) continue;
    slots[i] = edit(slots[i]);
    hit = true;
  }
  if (hit) routines[index] = _withSlots(routines[index], slots);
  return hit;
}

bool _editPhase(
  List<Program> programs,
  String phaseId,
  Phase Function(Phase) edit,
) {
  for (var i = 0; i < programs.length; i++) {
    final program = programs[i];
    final index = program.phases.indexWhere((p) => p.id == phaseId);
    if (index == -1) continue;
    final phases = [...program.phases];
    phases[index] = edit(phases[index]);
    programs[i] = _programWith(program, phases: phases);
    return true;
  }
  return false;
}

Routine _withSlots(Routine routine, List<ExerciseSlot> slots) => Routine(
  id: routine.id,
  name: routine.name,
  description: routine.description,
  slots: slots,
);

ExerciseSlot _slotWith(
  ExerciseSlot slot, {
  String? exerciseId,
  List<SetSpec>? sets,
  Progression? progression,
}) => ExerciseSlot(
  exerciseId: exerciseId ?? slot.exerciseId,
  sets: sets ?? slot.sets,
  restSeconds: slot.restSeconds,
  note: slot.note,
  progression: progression ?? slot.progression,
  optional: slot.optional,
);

Phase _phaseWith(
  Phase phase, {
  String? name,
  int? weeks,
  String? description,
  String? goal,
}) => Phase(
  id: phase.id,
  name: name ?? phase.name,
  weeks: weeks ?? phase.weeks,
  schedule: phase.schedule,
  description: description ?? phase.description,
  goal: goal ?? phase.goal,
);

Program _programWith(
  Program program, {
  String? name,
  String? description,
  String? rationale,
  List<Phase>? phases,
}) => Program(
  id: program.id,
  name: name ?? program.name,
  description: description ?? program.description,
  domain: program.domain,
  author: program.author,
  tags: program.tags,
  phases: phases ?? program.phases,
  rationale: rationale ?? program.rationale,
);
