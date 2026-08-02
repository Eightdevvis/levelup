import 'package:flutter_test/flutter_test.dart';
import 'package:programs/data/demo_bundle.dart';
import 'package:programs/data/tag_round.dart';
import 'package:programs/model/exercise.dart';
import 'package:programs/engine/resolver.dart';
import 'package:programs/model/library.dart';
import 'package:programs/model/program.dart';
import 'package:programs/model/target.dart';

/// Das Testprogramm ist nur so viel wert, wie es tatsächlich zeigt.
///
/// Dieser Test hält fest, dass jede Funktion darin vorkommt — sonst wächst
/// die App und der Prüfstand bleibt zurück, ohne dass es jemandem auffällt.
void main() {
  final bundle = demoBundle();
  final library = const Library().merge(bundle);
  final program = bundle.programs.single;

  _isolationTests();

  group('Testprogramm', () {
    test('ist vollständig verdrahtet', () {
      expect(library.missingReferences(program.id), isEmpty);
    });

    test('jeder Tag jeder Phase lässt sich auflösen', () {
      final resolver = ProgramResolver(library);
      for (var day = 0; day < program.totalDays; day++) {
        final aufgeloest = resolver.resolveDay(program, day);
        expect(aufgeloest, isNotNull, reason: 'Tag $day');
        // Kein Platzhalter: jede Übung des Tages steht wirklich in der
        // Bibliothek. Genau das prüft der Prüfstand an sich selbst.
        for (final item in aufgeloest!.items) {
          expect(
            item.exercise.name,
            isNot('Unbekannte Übung'),
            reason: 'Tag $day',
          );
        }
      }
    });

    test('zeigt alle vier Zieltypen', () {
      final kinds = {
        for (final routine in bundle.routines)
          for (final slot in routine.slots)
            for (final set in slot.sets) set.target.kind,
      };
      expect(kinds, containsAll(['duration', 'reps', 'quota', 'open']));
    });

    test('zeigt Last, mehrere Sätze, Pause, Notiz und Kür', () {
      final slots = [for (final r in bundle.routines) ...r.slots];

      expect(slots.any((s) => s.sets.any((x) => x.load != null)), isTrue);
      expect(slots.any((s) => s.sets.length > 1), isTrue);
      expect(slots.any((s) => s.restSeconds > 0), isTrue);
      expect(slots.any((s) => s.note != null), isTrue);
      expect(slots.any((s) => s.optional), isTrue);
    });

    test('zeigt beide Steigerungsarten', () {
      final arten = {
        for (final r in bundle.routines)
          for (final s in r.slots) s.progression.kind,
      };
      expect(arten, containsAll(['none', 'linear', 'table']));
    });

    test('zeigt beide Tagespläne', () {
      final arten = {for (final phase in program.phases) phase.schedule.kind};
      expect(arten, containsAll(['cycle', 'everyDay']));
    });

    test('zeigt Pausentage, Medien und eine karge Übung', () {
      final tage = [
        for (final phase in program.phases)
          if (phase.schedule case final CycleSchedule c) ...c.days,
      ];
      expect(tage.any((t) => t.isRest), isTrue);

      expect(bundle.exercises.any((e) => e.media.isNotEmpty), isTrue);
      expect(bundle.exercises.any((e) => e.cues.isNotEmpty), isTrue);
      expect(bundle.exercises.any((e) => e.equipment.isNotEmpty), isTrue);
      // Und den Gegenfall: eine Übung ohne alles.
      expect(
        bundle.exercises.any(
          (e) => e.benefits.isEmpty && e.cues.isEmpty && e.equipment.isEmpty,
        ),
        isTrue,
      );
    });

    test('die Steigerung greift wirklich über die Wochen', () {
      final einheit = library.routines['demo-e2']!;
      final dauer = einheit.slots.first;

      expect(
        (dauer.setsForWeek(0).single.target as DurationTarget).seconds,
        60,
      );
      expect(
        (dauer.setsForWeek(2).single.target as DurationTarget).seconds,
        90,
      );
      // Gedeckelt bei zwei Minuten, damit eine lange Phase nicht entgleist.
      expect(
        (dauer.setsForWeek(9).single.target as DurationTarget).seconds,
        120,
      );
    });

    test('trägt Kennungen, die sich vom echten Bestand unterscheiden', () {
      for (final exercise in bundle.exercises) {
        expect(exercise.id, startsWith('demo-'));
      }
      expect(program.id, startsWith('demo-'));
    });

    test('überlebt die Rundreise durch JSON', () {
      final wieder = Bundle.fromJson(bundle.toJson());
      expect(wieder.exercises, hasLength(bundle.exercises.length));
      expect(wieder.routines, hasLength(bundle.routines.length));
      expect(wieder.programs.single.totalDays, program.totalDays);
    });
  });
}

/// Der Prüfstand darf den Chat-Import nicht verunreinigen.
void _isolationTests() {
  test('Demo-Übungen bleiben aus dem Tag-Pool draußen', () {
    final gemischt = [
      ...demoBundle().exercises,
      const Exercise(id: 'echt', name: 'Echt', tags: ['geige', 'intonation']),
    ];
    final tags = tagPool(gemischt).map((t) => t.tag);

    expect(tags, containsAll(['geige', 'intonation']));
    expect(tags, isNot(contains('demo')));
    expect(tags, isNot(contains('player')));
  });

  test('und werden auch nicht als Treffer eingesetzt', () {
    // Genau die Tags einer Demo-Übung angefordert.
    final round = parseRoundOne('1. ["demo", "dauer", "player"]');
    final result = resolveRequests(round, demoBundle().exercises);

    expect(result.resolved, isEmpty);
    expect(result.unmatched, hasLength(1));
  });
}
