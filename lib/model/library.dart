import 'exercise.dart';
import 'program.dart';

/// Aktuelle Version des Austauschformats. Wird beim Import geprüft, damit
/// alte Bundles später migriert statt stillschweigend falsch gelesen werden.
const int kBundleVersion = 1;

/// Alles, was die App kennt: Übungen, Listen, Programme.
///
/// Übungen und Listen liegen bewusst getrennt von den Programmen, damit
/// dieselbe Übung in beliebig vielen Listen und dieselbe Liste in beliebig
/// vielen Programmen auftauchen kann — genau die Wiederverwendung, um die es
/// bei der Übungsdatenbank geht.
class Library {
  const Library({
    this.exercises = const {},
    this.routines = const {},
    this.programs = const {},
  });

  final Map<String, Exercise> exercises;
  final Map<String, Routine> routines;
  final Map<String, Program> programs;

  Exercise exercise(String id) => exercises[id] ?? Exercise.placeholder(id);

  Routine? routine(String id) => routines[id];

  Program? program(String id) => programs[id];

  bool get isEmpty => exercises.isEmpty && routines.isEmpty && programs.isEmpty;

  /// Legt ein Bundle über die Bibliothek. Gleiche IDs werden überschrieben —
  /// ein erneuter Import derselben Quelle aktualisiert also, statt zu doppeln.
  Library merge(Bundle bundle) => Library(
    exercises: {...exercises, for (final e in bundle.exercises) e.id: e},
    routines: {...routines, for (final r in bundle.routines) r.id: r},
    programs: {...programs, for (final p in bundle.programs) p.id: p},
  );

  Library withoutProgram(String id) => Library(
    exercises: exercises,
    routines: routines,
    programs: {...programs}..remove(id),
  );

  Bundle toBundle() => Bundle(
    exercises: exercises.values.toList(growable: false),
    routines: routines.values.toList(growable: false),
    programs: programs.values.toList(growable: false),
  );

  /// Bundle mit genau dem, was [programId] braucht — für Export und Weitergabe.
  Bundle bundleForProgram(String programId) {
    final program = programs[programId];
    if (program == null) return const Bundle();

    final usedRoutines = <Routine>[];
    final usedExerciseIds = <String>{};
    for (final id in program.routineIds) {
      final routine = routines[id];
      if (routine == null) continue;
      usedRoutines.add(routine);
      usedExerciseIds.addAll(routine.slots.map((s) => s.exerciseId));
    }

    return Bundle(
      exercises: usedExerciseIds
          .map((id) => exercises[id])
          .whereType<Exercise>()
          .toList(growable: false),
      routines: usedRoutines,
      programs: [program],
    );
  }

  /// Findet, was ein Programm braucht, aber die Bibliothek nicht hat.
  /// Genau das, was ein unvollständiger AI-Import produziert.
  List<String> missingReferences(String programId) {
    final program = programs[programId];
    if (program == null) return ['Programm $programId fehlt'];

    final problems = <String>[];
    for (final id in program.routineIds) {
      final routine = routines[id];
      if (routine == null) {
        problems.add('Liste "$id" fehlt');
        continue;
      }
      for (final slot in routine.slots) {
        if (!exercises.containsKey(slot.exerciseId)) {
          problems.add(
            'Übung "${slot.exerciseId}" (in "${routine.name}") fehlt',
          );
        }
      }
    }
    return problems;
  }
}

/// Das Austauschformat: eine Datei, die Übungen, Listen und Programme
/// zusammen transportiert.
///
/// Das ist zugleich das Format, das eine AI ausgibt — deshalb sind alle drei
/// Ebenen in einem Dokument, damit ein generierter Plan seine Übungen gleich
/// mitbringt und nicht auf eine vorhandene Datenbank angewiesen ist.
class Bundle {
  const Bundle({
    this.exercises = const [],
    this.routines = const [],
    this.programs = const [],
    this.version = kBundleVersion,
  });

  final List<Exercise> exercises;
  final List<Routine> routines;
  final List<Program> programs;
  final int version;

  bool get isEmpty => exercises.isEmpty && routines.isEmpty && programs.isEmpty;

  Map<String, dynamic> toJson() => {
    'version': version,
    'exercises': exercises.map((e) => e.toJson()).toList(),
    'routines': routines.map((e) => e.toJson()).toList(),
    'programs': programs.map((e) => e.toJson()).toList(),
  };

  static Bundle fromJson(Map<String, dynamic> json) {
    final version = (json['version'] as num?)?.round() ?? kBundleVersion;
    if (version > kBundleVersion) {
      throw FormatException(
        'Bundle-Version $version ist neuer als diese App-Version '
        '($kBundleVersion). Bitte App aktualisieren.',
      );
    }
    return Bundle(
      version: version,
      exercises: (json['exercises'] as List<dynamic>? ?? const [])
          .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      routines: (json['routines'] as List<dynamic>? ?? const [])
          .map((e) => Routine.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      programs: (json['programs'] as List<dynamic>? ?? const [])
          .map((e) => Program.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}
