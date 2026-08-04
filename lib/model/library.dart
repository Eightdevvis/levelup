import 'exercise.dart';
import 'program.dart';

/// Aktuelle Version des Austauschformats. Wird beim Import geprüft, damit
/// alte Bundles später migriert statt stillschweigend falsch gelesen werden.
/// 2 seit dem Umbau des Übungsobjekts: `summary` und `instructions` sind zu
/// `description` verschmolzen, `requirements` heißt `equipment`, `domain` ist
/// weg (Spec §2.1). Ältere Bundles werden beim Lesen übersetzt; umgekehrt geht
/// es nicht, deshalb die neue Zahl — eine alte App-Version soll sich weigern,
/// statt die Texte stillschweigend zu verlieren.
const int kBundleVersion = 2;

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
  ///
  /// Bei Einheiten gilt das nur innerhalb desselben Programms: eine Einheit
  /// gehört zu genau einem Plan, und zwei Pläne, die zufällig dieselbe Kennung
  /// vergeben, dürfen sich nicht gegenseitig auslöschen. Siehe [_entwirrt].
  Library merge(Bundle bundle) {
    final sauber = _entwirrt(bundle);
    return Library(
      exercises: {...exercises, for (final e in sauber.exercises) e.id: e},
      routines: {...routines, for (final r in sauber.routines) r.id: r},
      programs: {...programs, for (final p in sauber.programs) p.id: p},
    );
  }

  /// Benennt hereinkommende Einheiten um, die fremde überschreiben würden.
  ///
  /// Eine KI nennt ihre Einheiten „e1", „e2", „woche1" — Kennungen, die nichts
  /// über den Plan sagen, zu dem sie gehören. Die Bibliothek führt Einheiten
  /// aber in einer einzigen Ablage. Ohne diese Prüfung überschriebe der zweite
  /// importierte Plan die Einheiten des ersten, und das ältere Programm zeigte
  /// beim Öffnen den Inhalt des neueren.
  ///
  /// Umbenannt wird die hereinkommende Seite, nie die vorhandene: was schon in
  /// der Bibliothek liegt und benutzt wird, bleibt unangetastet. Gehört die
  /// bestehende Einheit zu einem Programm, das dieses Bundle ohnehin ersetzt,
  /// ist es keine Kollision, sondern eine Aktualisierung.
  Bundle _entwirrt(Bundle bundle) {
    if (bundle.routines.isEmpty) return bundle;

    final ersetzte = bundle.programs.map((p) => p.id).toSet();
    final fremd = <String>{
      for (final program in programs.values)
        if (!ersetzte.contains(program.id)) ...program.routineIds,
    };

    final namen = <String, String>{};
    for (final routine in bundle.routines) {
      if (!fremd.contains(routine.id)) continue;
      final besitzer = bundle.programs
          .where((p) => p.routineIds.contains(routine.id))
          .map((p) => p.id)
          .firstOrNull;
      namen[routine.id] = '${besitzer ?? 'import'}-${routine.id}';
    }
    if (namen.isEmpty) return bundle;

    return Bundle(
      version: bundle.version,
      personalNote: bundle.personalNote,
      exercises: bundle.exercises,
      routines: [
        for (final r in bundle.routines)
          namen.containsKey(r.id)
              ? Routine(
                  id: namen[r.id]!,
                  name: r.name,
                  description: r.description,
                  slots: r.slots,
                )
              : r,
      ],
      programs: [for (final p in bundle.programs) p.renamed(namen)],
    );
  }

  Library withoutProgram(String id) => Library(
    exercises: exercises,
    routines: routines,
    programs: {...programs}..remove(id),
  );

  /// Alles, worauf kein Programm mehr zeigt.
  ///
  /// Beim Löschen eines Programms bleiben seine Übungen absichtlich liegen —
  /// sie sind der wertvolle Teil und sollen ein versehentlich gelöschtes
  /// Programm überleben. Über die Zeit sammelt sich dadurch aber Bestand an,
  /// den niemand mehr sieht und der trotzdem im Tag-Pool mitzählt. Deshalb
  /// sichtbar aufräumbar statt automatisch weggeräumt.
  ({Set<String> exercises, Set<String> routines}) get orphans {
    final benutzteRoutinen = <String>{
      for (final program in programs.values) ...program.routineIds,
    };
    final benutzteUebungen = <String>{
      for (final id in benutzteRoutinen)
        ...?routines[id]?.slots.map((s) => s.exerciseId),
    };

    return (
      exercises: exercises.keys.where((id) => !benutzteUebungen.contains(id)).toSet(),
      routines: routines.keys.where((id) => !benutzteRoutinen.contains(id)).toSet(),
    );
  }

  /// Die Bibliothek ohne das, worauf nichts mehr zeigt.
  Library withoutOrphans() {
    final weg = orphans;
    return Library(
      exercises: {
        for (final e in exercises.entries)
          if (!weg.exercises.contains(e.key)) e.key: e.value,
      },
      routines: {
        for (final r in routines.entries)
          if (!weg.routines.contains(r.key)) r.key: r.value,
      },
      programs: programs,
    );
  }

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
    this.personalNote,
  });

  final List<Exercise> exercises;
  final List<Routine> routines;
  final List<Program> programs;
  final int version;

  /// Was die AI dem Nutzer persönlich zum Plan gesagt hat.
  ///
  /// Der einzige Teil des Bundles, der nicht öffentlich ist: alles andere
  /// wandert beim Annehmen in die geteilte Bibliothek und ist deshalb
  /// allgemein formuliert. Hier steht, was nur diesen einen Menschen angeht —
  /// und genau das wird vor dem Teilen entfernt.
  final String? personalNote;

  bool get isEmpty => exercises.isEmpty && routines.isEmpty && programs.isEmpty;

  Map<String, dynamic> toJson() => {
    'version': version,
    if (personalNote != null) 'personalNote': personalNote,
    'exercises': exercises.map((e) => e.toJson()).toList(),
    'routines': routines.map((e) => e.toJson()).toList(),
    'programs': programs.map((e) => e.toJson()).toList(),
  };

  /// Dasselbe Bundle ohne den persönlichen Teil — die Fassung, die geteilt
  /// werden darf.
  Bundle get shareable => personalNote == null
      ? this
      : Bundle(
          exercises: exercises,
          routines: routines,
          programs: programs,
          version: version,
        );

  static Bundle fromJson(Map<String, dynamic> json) {
    final version = (json['version'] as num?)?.round() ?? kBundleVersion;
    if (version > kBundleVersion) {
      throw FormatException(
        'Bundle-Version $version ist neuer als diese App-Version '
        '($kBundleVersion). Bitte App aktualisieren.',
      );
    }
    final note = json['personalNote'];
    return Bundle(
      version: version,
      personalNote: note is String && note.trim().isNotEmpty ? note.trim() : null,
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
