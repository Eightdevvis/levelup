import 'package:flutter_test/flutter_test.dart';
import 'package:programs/data/seed.dart';
import 'package:programs/engine/resolver.dart';
import 'package:programs/model/exercise.dart';
import 'package:programs/model/library.dart';
import 'package:programs/model/program.dart';
import 'package:programs/model/progression.dart';
import 'package:programs/model/set_spec.dart';
import 'package:programs/model/target.dart';

/// Kleines Testprogramm: Phase A hat jeden Tag dieselbe Liste,
/// Phase B wechselt zwischen zwei Listen und hat einen Pausentag.
Library _fixture() {
  const exercises = [
    Exercise(id: 'e1', name: 'Übung eins'),
    Exercise(id: 'e2', name: 'Übung zwei'),
  ];

  const routines = [
    Routine(
      id: 'r1',
      name: 'Liste eins',
      slots: [
        ExerciseSlot(
          exerciseId: 'e1',
          sets: [SetSpec(target: RepsTarget(reps: 10))],
          progression: LinearProgression(
            field: ProgressionField.target,
            amount: 2,
          ),
        ),
      ],
    ),
    Routine(
      id: 'r2',
      name: 'Liste zwei',
      slots: [
        ExerciseSlot(
          exerciseId: 'e2',
          sets: [SetSpec(target: DurationTarget(seconds: 60))],
        ),
      ],
    ),
  ];

  final program = Program(
    id: 'p1',
    name: 'Testprogramm',
    phases: [
      const Phase(
        id: 'a',
        name: 'Phase A',
        weeks: 2,
        schedule: EveryDaySchedule(routineId: 'r1', daysPerWeek: 3),
      ),
      Phase(
        id: 'b',
        name: 'Phase B',
        weeks: 2,
        schedule: CycleSchedule(
          days: [
            const DaySlot(routineId: 'r1'),
            const DaySlot(routineId: 'r2'),
            DaySlot.rest(),
          ],
        ),
      ),
    ],
  );

  return const Library().merge(
    Bundle(exercises: exercises, routines: routines, programs: [program]),
  );
}

void main() {
  final library = _fixture();
  final resolver = ProgramResolver(library);
  final program = library.program('p1')!;

  group('Programmlänge', () {
    test('zählt Wochen und Tage über alle Phasen', () {
      expect(program.totalWeeks, 4);
      // Phase A: 2 Wochen à 3 Tage, Phase B: 2 Wochen à 3 Tage
      expect(program.totalDays, 12);
    });
  });

  group('Tag-Adressierung', () {
    test('erster Tag liegt in Phase 0, Woche 0', () {
      final ref = resolver.dayRefFor(program, 0)!;
      expect(ref.phaseIndex, 0);
      expect(ref.weekInPhase, 0);
      expect(ref.dayInCycle, 0);
    });

    test('Tag 3 beginnt die zweite Woche derselben Phase', () {
      final ref = resolver.dayRefFor(program, 3)!;
      expect(ref.phaseIndex, 0);
      expect(ref.weekInPhase, 1);
      expect(ref.dayInCycle, 0);
    });

    test('Tag 6 wechselt in die zweite Phase und setzt die Woche zurück', () {
      final ref = resolver.dayRefFor(program, 6)!;
      expect(ref.phaseIndex, 1);
      expect(ref.weekInPhase, 0);
      expect(ref.dayInCycle, 0);
    });

    test('hinter dem Programmende kommt null', () {
      expect(resolver.dayRefFor(program, 12), isNull);
      expect(resolver.dayRefFor(program, -1), isNull);
    });
  });

  group('Auflösung eines Tages', () {
    test('EveryDay liefert an jedem Tag dieselbe Liste', () {
      for (var day = 0; day < 6; day++) {
        final resolved = resolver.resolveDay(program, day)!;
        expect(resolved.routine!.id, 'r1');
      }
    });

    test('Zyklus verteilt die Listen und kennt den Pausentag', () {
      expect(resolver.resolveDay(program, 6)!.routine!.id, 'r1');
      expect(resolver.resolveDay(program, 7)!.routine!.id, 'r2');

      final rest = resolver.resolveDay(program, 8)!;
      expect(rest.isRest, isTrue);
      expect(rest.items, isEmpty);
    });

    test('Übungsobjekte werden aus der Bibliothek gezogen', () {
      final day = resolver.resolveDay(program, 0)!;
      expect(day.items.single.exercise.name, 'Übung eins');
      expect(day.items.single.isMissing, isFalse);
    });
  });

  group('Progression über die Wochen', () {
    test('greift innerhalb der Phase', () {
      final week0 = resolver.resolveDay(program, 0)!;
      final week1 = resolver.resolveDay(program, 3)!;
      expect((week0.items.single.sets.single.target as RepsTarget).reps, 10);
      expect((week1.items.single.sets.single.target as RepsTarget).reps, 12);
    });

    test('startet in der nächsten Phase wieder bei null', () {
      // Tag 6 ist Phase B, Woche 0 — dieselbe Liste r1, aber neue Phase.
      final phaseB = resolver.resolveDay(program, 6)!;
      expect((phaseB.items.single.sets.single.target as RepsTarget).reps, 10);
    });
  });

  group('Wochen- und Phasenansicht', () {
    test('resolveWeek liefert genau einen Zyklus', () {
      final week = resolver.resolveWeek(program, 1, 0);
      expect(week.length, 3);
      expect(week[2].isRest, isTrue);
    });

    test('resolvePhase liefert alle Tage der Phase', () {
      expect(resolver.resolvePhase(program, 0).length, 6);
    });

    test('phaseStartDay zeigt auf den ersten Tag der Phase', () {
      expect(resolver.phaseStartDay(program, 0), 0);
      expect(resolver.phaseStartDay(program, 1), 6);
    });
  });

  group('Fehlende Verweise', () {
    test('unbekannte Übung wird zum Platzhalter statt zum Absturz', () {
      final broken = const Library().merge(
        const Bundle(
          routines: [
            Routine(
              id: 'r',
              name: 'L',
              slots: [
                ExerciseSlot(
                  exerciseId: 'gibtsnicht',
                  sets: [SetSpec(target: RepsTarget(reps: 5))],
                ),
              ],
            ),
          ],
          programs: [
            Program(
              id: 'p',
              name: 'P',
              phases: [
                Phase(
                  id: 'ph',
                  name: 'Phase',
                  weeks: 1,
                  schedule: EveryDaySchedule(routineId: 'r', daysPerWeek: 1),
                ),
              ],
            ),
          ],
        ),
      );

      final day = ProgramResolver(broken).resolveDay(broken.program('p')!, 0)!;
      expect(day.items.single.isMissing, isTrue);
      expect(broken.missingReferences('p'), isNotEmpty);
    });

    test('fehlende Liste macht den Tag sichtbar kaputt, nicht still leer', () {
      final broken = const Library().merge(
        const Bundle(
          programs: [
            Program(
              id: 'p',
              name: 'P',
              phases: [
                Phase(
                  id: 'ph',
                  name: 'Phase',
                  weeks: 1,
                  schedule: EveryDaySchedule(routineId: 'weg', daysPerWeek: 1),
                ),
              ],
            ),
          ],
        ),
      );

      final day = ProgramResolver(broken).resolveDay(broken.program('p')!, 0)!;
      expect(day.label, contains('fehlt'));
    });
  });

  group('Startinhalte', () {
    final seeded = const Library().merge(seedBundle());

    test('alle Seed-Programme sind vollständig verdrahtet', () {
      expect(seeded.programs, isNotEmpty);
      for (final program in seeded.programs.values) {
        expect(
          seeded.missingReferences(program.id),
          isEmpty,
          reason: 'Programm "${program.name}" hat lose Verweise',
        );
      }
    });

    test('decken mehrere Domänen mit demselben Modell ab', () {
      final domains = seeded.programs.values.map((p) => p.domain).toSet();
      expect(domains.length, greaterThanOrEqualTo(4));
    });

    test('jeder Tag jedes Programms lässt sich auflösen', () {
      final seedResolver = ProgramResolver(seeded);
      for (final program in seeded.programs.values) {
        for (var day = 0; day < program.totalDays; day++) {
          expect(
            seedResolver.resolveDay(program, day),
            isNotNull,
            reason: '${program.name}, Tag $day',
          );
        }
      }
    });
  });
}
