import 'package:flutter_test/flutter_test.dart';
import 'package:programs/data/chat_prompts.dart';
import 'package:programs/data/plan_round.dart';
import 'package:programs/data/tag_round.dart';
import 'package:programs/model/exercise.dart';
import 'package:programs/model/library.dart';
import 'package:programs/model/program.dart';

/// Der kostenlose Weg in zwei Runden.
///
/// Geprüft wird vor allem, was eine KI-Antwort in freier Wildbahn anrichtet:
/// Code-Zäune, „hier bitteschön"-Vorreden, einfache statt doppelter
/// Anführungszeichen, Schlüssel ohne Anführungszeichen. Wer das dem Nutzer
/// zum Wegschneiden überlässt, bekommt Fehlerberichte über den Parser.

Exercise ex(String id, String name, List<String> tags) {
  return Exercise(
    id: id,
    name: name,
    description: 'Mach $name.',
    tags: tags,
  );
}

final bibliothek = [
  ex('geige-aufnahme-hoeren', 'Acht Takte aufnehmen und anhören', [
    'geige',
    'rueckkopplung',
    'aufnahme',
  ]),
  ex('geige-bordun', 'Tonleiter über Bordunton', [
    'geige',
    'intonation',
    'tonleiter',
  ]),
  ex('kraft-video', 'Satz von der Seite filmen', [
    'krafttraining',
    'rueckkopplung',
    'video',
  ]),
];

void main() {
  _migrationTests();
  _orphanTests();

  group('Tag-Pool', () {
    test('zählt und sortiert nach Häufigkeit', () {
      final pool = tagPool(bibliothek);
      expect(pool.first.tag, 'geige');
      expect(pool.first.count, 2);
      // rueckkopplung kommt ebenfalls zweimal vor.
      expect(pool.map((t) => t.tag).take(2), containsAll(['geige', 'rueckkopplung']));
      expect(pool.map((t) => t.tag), contains('tonleiter'));
    });

    test('ist leer, wenn die Bibliothek leer ist', () {
      expect(tagPool(const []), isEmpty);
    });

    test('normalisiert Schreibweisen zu einem Tag', () {
      final pool = tagPool([
        ex('a', 'A', ['Geige', 'geige ']),
      ]);
      expect(pool.where((t) => t.tag == 'geige'), hasLength(1));
    });
  });

  group('Runde 1 lesen', () {
    test('liest nummerierte Tag-Mengen', () {
      final result = parseRoundOne('''
1. ["geige", "rueckkopplung", "aufnahme"]
2. ["geige", "intonation"]
''');
      expect(result.problems, isEmpty);
      expect(result.requests, hasLength(2));
      expect((result.requests.first as TagRequest).tags, [
        'geige',
        'rueckkopplung',
        'aufnahme',
      ]);
    });

    test('verträgt Code-Zäune und eine Vorrede', () {
      final result = parseRoundOne('''
Klar, hier bitteschön:

```json
1. ["geige", "aufnahme"]
2. ["geige", "bogen"]
```
''');
      // Die Vorrede ist eine eigene Zeile ohne Nummer und wird bemängelt,
      // nicht verschluckt — die beiden Übungen kommen trotzdem an.
      expect(result.requests, hasLength(2));
    });

    test('liest eine selbst geschriebene Übung', () {
      final result = parseRoundOne('''
1. {
     "name": "Bogen im Spiegel führen",
     "description": "Lange Striche vor dem Spiegel.",
     "instructions": ["Stell dich seitlich vor den Spiegel.", "Spiel lange Striche."],
     "benefits": ["Du siehst die Abweichung"],
     "equipment": ["Spiegel"],
     "tags": ["geige", "bogen", "haltung"]
   }
''');
      expect(result.problems, isEmpty);
      final draft = result.requests.single as DraftRequest;
      expect(draft.exercise.name, 'Bogen im Spiegel führen');
      expect(draft.exercise.id, 'geige-bogen-im-spiegel-fuehren');
      // summary und instructions fließen zu einem description zusammen.
      expect(draft.exercise.lines, hasLength(3));
      expect(draft.exercise.equipment, ['Spiegel']);
      expect(draft.exercise.tags, ['geige', 'bogen', 'haltung']);
    });

    test('verträgt einfache Anführungszeichen und nackte Schlüssel', () {
      final result = parseRoundOne('''
1. {
     name: 'Leersaiten stimmen',
     tags: ['geige', 'stimmen'],
     description: 'Stimme nach Gehör, prüfe danach.'
   }
''');
      final draft = result.requests.single as DraftRequest;
      expect(draft.exercise.name, 'Leersaiten stimmen');
      expect(draft.exercise.description, 'Stimme nach Gehör, prüfe danach.');
    });

    test('benennt eine Übung ohne Tags, statt sie zu verschlucken', () {
      final result = parseRoundOne('1. {"name": "Ohne Tags"}');
      expect(result.requests, isEmpty);
      expect(result.problems.single, contains('nicht lesbar'));
    });

    test('verträgt Aufzählungsstriche statt Zahlen', () {
      final result = parseRoundOne('''
- ["geige", "aufnahme"]
- ["geige", "bogen"]
''');
      expect(result.requests, hasLength(2));
    });
  });

  group('Auflösen gegen die Bibliothek', () {
    test('findet die Übung über ihre Tags, nicht über den Namen', () {
      final round = parseRoundOne('1. ["geige", "rueckkopplung", "aufnahme"]');
      final result = resolveRequests(round, bibliothek);

      expect(result.resolved.single.exercise.id, 'geige-aufnahme-hoeren');
      expect(result.resolved.single.isNew, isFalse);
      expect(result.reused, 1);
      expect(result.created, 0);
    });

    test('nimmt keine Übung aus fremder Tätigkeit', () {
      // Zwei von drei Tags stimmen mit dem Kraft-Baustein überein — aber es
      // geht um Geige. Jaccard 2/4 = 0,5 liegt unter der Schwelle.
      final round = parseRoundOne('1. ["geige", "rueckkopplung", "video"]');
      final result = resolveRequests(round, bibliothek);

      expect(result.resolved, isEmpty);
      expect(result.unmatched.single, contains('geige'));
    });

    test('meldet eine Tag-Menge ohne Treffer, statt still zu übergehen', () {
      final round = parseRoundOne('1. ["klavier", "fingersatz"]');
      final result = resolveRequests(round, bibliothek);

      expect(result.resolved, isEmpty);
      expect(result.unmatched, hasLength(1));
    });

    test('legt eine geschriebene Übung an, wenn nichts passt', () {
      final round = parseRoundOne(
        '1. {"name": "Vibrato lösen", "tags": ["geige", "vibrato", "linke_hand"]}',
      );
      final result = resolveRequests(round, bibliothek);

      expect(result.created, 1);
      expect(result.resolved.single.isNew, isTrue);
      expect(result.resolved.single.exercise.tags, contains('vibrato'));
    });

    test('erzeugt dieselbe Übung nicht zweimal im selben Import', () {
      // Die KI schreibt sie einmal aus und verweist später über Tags darauf.
      final round = parseRoundOne('''
1. {"name": "Vibrato lösen", "tags": ["geige", "vibrato", "linke_hand"]}
2. ["geige", "vibrato", "linke_hand"]
''');
      final result = resolveRequests(round, bibliothek);

      expect(result.created, 1);
      expect(result.resolved, hasLength(2));
      expect(
        result.resolved[0].exercise.id,
        result.resolved[1].exercise.id,
      );
    });

    test('leere Bibliothek: alles Geschriebene kommt durch', () {
      final round = parseRoundOne('''
1. {"name": "Erste Übung", "tags": ["sprechen", "aufnahme"]}
2. {"name": "Zweite Übung", "tags": ["sprechen", "struktur"]}
''');
      final result = resolveRequests(round, const []);

      expect(result.created, 2);
      expect(result.unmatched, isEmpty);
    });

    test('Ähnlichkeit ist symmetrisch und kennt ihre Ränder', () {
      expect(tagSimilarity(['a', 'b'], ['a', 'b']), 1);
      expect(tagSimilarity(['a'], ['b']), 0);
      expect(tagSimilarity(const [], ['a']), 0);
      expect(tagSimilarity(['a', 'b'], ['b', 'c']), closeTo(1 / 3, 0.001));
    });
  });

  group('Runde 2 lesen', () {
    List<Resolved> aufgeloest() {
      final round = parseRoundOne(
        '1. ["geige", "rueckkopplung", "aufnahme"]\n'
        '2. ["geige", "intonation", "tonleiter"]',
      );
      return resolveRequests(round, bibliothek).resolved;
    }

    test('baut ein vollständiges Bundle', () {
      final result = parseRoundTwo('''
```json
{
  "program": {
    "name": "Gehör zuerst",
    "domain": "geige",
    "description": "Erst hören, dann spielen.",
    "rationale": "Das Problem ist die Intonation, nicht das Stück.",
    "phases": [
      {"name": "Aufbau", "weeks": 4, "goal": "Hört Abweichungen im Mitschnitt",
       "days": ["e1", "pause", "e2", "pause", "e1", "pause", "pause"]}
    ]
  },
  "units": [
    {"id": "e1", "name": "Hören", "exercises": [
      {"id": "geige-aufnahme-hoeren", "minutes": 10, "note": "Langsam anfangen"}]},
    {"id": "e2", "name": "Intonation", "exercises": [
      {"id": "geige-bordun", "minutes": 15}]}
  ]
}
```
''', aufgeloest());

      expect(result.error, isNull);
      expect(result.ok, isTrue);

      final bundle = result.bundle!;
      expect(bundle.programs.single.name, 'Gehör zuerst');
      expect(bundle.programs.single.rationale, contains('Intonation'));
      expect(bundle.routines, hasLength(2));
      expect(bundle.exercises, hasLength(2));

      final phase = bundle.programs.single.phases.single;
      expect(phase.weeks, 4);
      expect(phase.schedule.cycleLength, 7);
      expect(phase.totalDays, 28);
      expect(phase.goal, contains('Mitschnitt'));

      final slot = bundle.routines.first.slots.first;
      expect(slot.note, 'Langsam anfangen');
    });

    test('macht aus Minuten eine Dauer und aus Wiederholungen Reps', () {
      final result = parseRoundTwo('''
{"program": {"name": "P", "phases": [{"name": "A", "days": ["e1"]}]},
 "units": [{"id": "e1", "exercises": [
   {"id": "geige-aufnahme-hoeren", "minutes": 5},
   {"id": "geige-bordun", "reps": 12}]}]}
''', aufgeloest());

      final slots = result.bundle!.routines.single.slots;
      expect(slots[0].sets.single.target.toJson(), {
        'kind': 'duration',
        'seconds': 300,
      });
      expect(slots[1].sets.single.target.toJson(), {'kind': 'reps', 'reps': 12});
    });

    test('übergeht eine erfundene Übungskennung und sagt es', () {
      final result = parseRoundTwo('''
{"program": {"name": "P", "phases": [{"name": "A", "days": ["e1"]}]},
 "units": [{"id": "e1", "exercises": [
   {"id": "geige-aufnahme-hoeren", "minutes": 5},
   {"id": "gibt-es-nicht", "minutes": 5}]}]}
''', aufgeloest());

      expect(result.ok, isTrue);
      expect(result.warnings.single, contains('gibt-es-nicht'));
      expect(result.bundle!.routines.single.slots, hasLength(1));
    });

    test('nimmt nur die Übungen mit, die auch vorkommen', () {
      final result = parseRoundTwo('''
{"program": {"name": "P", "phases": [{"name": "A", "days": ["e1"]}]},
 "units": [{"id": "e1", "exercises": [{"id": "geige-bordun", "minutes": 5}]}]}
''', aufgeloest());

      // Zwei waren aufgelöst, nur eine steht im Plan.
      expect(result.bundle!.exercises, hasLength(1));
      expect(result.bundle!.exercises.single.id, 'geige-bordun');
    });

    test('meldet fehlendes program statt eines leeren Bundles', () {
      final result = parseRoundTwo('{"units": []}', aufgeloest());
      expect(result.ok, isFalse);
      expect(result.error, contains('program'));
    });

    test('meldet kaputtes JSON verständlich', () {
      final result = parseRoundTwo('{kaputt', aufgeloest());
      expect(result.ok, isFalse);
      expect(result.error, contains('JSON'));
    });

    test('gibt jeder Einheit eine Kennung, die zum Programm gehört', () {
      final result = parseRoundTwo('''
{"program": {"name": "Gehör zuerst", "tags": ["geige"],
   "phases": [{"name": "A", "days": ["e1", "pause"]}]},
 "units": [{"id": "e1", "exercises": [{"id": "geige-bordun", "minutes": 5}]}]}
''', aufgeloest());

      final programId = result.bundle!.programs.single.id;
      final routineId = result.bundle!.routines.single.id;

      // Die KI nennt ihre Einheiten „e1", „e2", „e3" — jede KI, jedes Mal.
      // Bliebe das so stehen, hätte der zweite importierte Plan dieselben
      // Kennungen wie der erste und überschriebe ihn in der Bibliothek.
      expect(routineId, startsWith(programId));
      expect(routineId, isNot('e1'));

      // Und der Tagesplan muss auf die neue Kennung zeigen, nicht auf die alte.
      final days =
          (result.bundle!.programs.single.phases.single.schedule
                  as CycleSchedule)
              .days;
      expect(days.first.routineId, routineId);
    });

    test('zwei Pläne kommen sich in der Bibliothek nicht ins Gehege', () {
      String plan(String name, String uebung) =>
          '{"program": {"name": "$name", "tags": ["geige"],'
          ' "phases": [{"name": "A", "days": ["e1"]}]},'
          ' "units": [{"id": "e1", "name": "Einheit von $name",'
          ' "exercises": [{"id": "$uebung", "minutes": 5}]}]}';

      final ersterPlan = parseRoundTwo(
        plan('Gehör zuerst', 'geige-bordun'),
        aufgeloest(),
      ).bundle!;
      final zweiterPlan = parseRoundTwo(
        plan('Bogen zuerst', 'geige-aufnahme-hoeren'),
        aufgeloest(),
      ).bundle!;

      final library = const Library().merge(ersterPlan).merge(zweiterPlan);

      // Genau der gemeldete Fehler: das ältere Programm öffnen und den Inhalt
      // des zuletzt importierten sehen.
      for (final bundle in [ersterPlan, zweiterPlan]) {
        final program = library.program(bundle.programs.single.id)!;
        final routine = library.routine(program.routineIds.single)!;
        expect(routine.name, bundle.routines.single.name);
        expect(
          routine.slots.single.exerciseId,
          bundle.routines.single.slots.single.exerciseId,
        );
      }
    });

    test('auch ein eingefügtes Bundle überschreibt keine fremde Einheit', () {
      // Nicht der Chat-Weg, sondern der Weg „fertiges Bundle einfügen": hier
      // erfindet die KI die Kennungen selbst, und niemand hält sie ab, „e1" zu
      // schreiben. Die Bibliothek muss das allein abfangen.
      Bundle bundle(String programId, String routineName) => Bundle(
        exercises: [ex('u-$programId', 'Übung', ['geige'])],
        routines: [
          Routine(
            id: 'e1',
            name: routineName,
            slots: [ExerciseSlot(exerciseId: 'u-$programId')],
          ),
        ],
        programs: [
          Program(
            id: programId,
            name: programId,
            tags: const ['geige'],
            phases: [
              Phase(
                id: '$programId-p1',
                name: 'A',
                weeks: 1,
                schedule: CycleSchedule(days: [DaySlot(routineId: 'e1')]),
              ),
            ],
          ),
        ],
      );

      final library = const Library()
          .merge(bundle('alt', 'Einheit des alten Plans'))
          .merge(bundle('neu', 'Einheit des neuen Plans'));

      final alt = library.program('alt')!;
      expect(
        library.routine(alt.routineIds.single)!.name,
        'Einheit des alten Plans',
      );

      final neu = library.program('neu')!;
      expect(
        library.routine(neu.routineIds.single)!.name,
        'Einheit des neuen Plans',
      );
      expect(library.missingReferences('alt'), isEmpty);
      expect(library.missingReferences('neu'), isEmpty);
    });

    test('derselbe Plan zweimal importiert bleibt ein Plan', () {
      final einmal = parseRoundTwo('''
{"program": {"name": "P", "tags": ["geige"],
   "phases": [{"name": "A", "days": ["e1"]}]},
 "units": [{"id": "e1", "exercises": [{"id": "geige-bordun", "minutes": 5}]}]}
''', aufgeloest()).bundle!;

      final library = const Library().merge(einmal).merge(einmal);

      // Erneut eingespielt ist eine Aktualisierung, keine Kollision — sonst
      // sammelte jeder zweite Versuch eine Kopie aller Einheiten an.
      expect(library.programs, hasLength(1));
      expect(library.routines, hasLength(1));
      expect(library.missingReferences(einmal.programs.single.id), isEmpty);
    });

    test('macht aus allem, was keine Einheit ist, einen freien Tag', () {
      final result = parseRoundTwo('''
{"program": {"name": "P", "phases": [{"name": "A",
   "days": ["e1", "rest", "frei", "pause"]}]},
 "units": [{"id": "e1", "exercises": [{"id": "geige-bordun", "minutes": 5}]}]}
''', aufgeloest());

      final days = (result.bundle!.programs.single.phases.single.schedule
              as CycleSchedule)
          .days;
      expect(days, hasLength(4));
      expect(days.where((d) => d.isRest), hasLength(3));
    });
  });

  group('Die Texte zum Kopieren', () {
    test('sagen beim leeren Pool, dass er leer ist', () {
      final text = buildTagPrompt(tagPool(const []));
      expect(text, contains('LEER'));
      expect(text, contains('schreibe jede Übung selbst aus'));
    });

    test('führen den Pool auf, wenn es einen gibt', () {
      final text = buildTagPrompt(tagPool(bibliothek));
      expect(text, contains('geige'));
      expect(text, contains('rueckkopplung'));
      expect(text, isNot(contains('LEER')));
    });

    test('nennen im Planprompt jede Übung mit ihrer Kennung', () {
      final round = parseRoundOne('1. ["geige", "rueckkopplung", "aufnahme"]');
      final resolved = resolveRequests(round, bibliothek).resolved;
      final text = buildPlanPrompt(resolved);

      expect(text, contains('geige-aufnahme-hoeren'));
      expect(text, contains('Acht Takte aufnehmen und anhören'));
      expect(text, contains('"units"'));
      expect(text, contains('erfinde keine'));
    });
  });
}

/// Auf den Geräten liegen Bibliotheken im alten Format. Sie stillschweigend
/// fallen zu lassen hieße, jedem seine Übungen zu leeren Hüllen zu machen.
void _migrationTests() {
  group('Altes Übungsformat lesen', () {
    test('macht aus summary und instructions ein description', () {
      final exercise = Exercise.fromJson({
        'id': 'alt',
        'name': 'Alte Übung',
        'domain': 'geige',
        'summary': 'Worum es geht.',
        'instructions': ['Schritt eins.', 'Schritt zwei.'],
        'requirements': ['Metronom'],
        'tags': ['notation'],
      });

      expect(
        exercise.description,
        'Worum es geht.\nSchritt eins.\nSchritt zwei.',
      );
      expect(exercise.lines, hasLength(3));
      expect(exercise.equipment, ['Metronom']);
      // domain fliegt raus, bleibt aber als erster Tag erhalten — sonst
      // verlöre die Übung ihre Tätigkeit und wäre nicht mehr auffindbar.
      expect(exercise.tags, ['geige', 'notation']);
      expect(exercise.domain, 'geige');
    });

    test('lässt eine bereits neue Übung unverändert', () {
      final exercise = Exercise.fromJson({
        'id': 'neu',
        'name': 'Neue Übung',
        'description': 'Tu dies.',
        'equipment': ['Handy'],
        'tags': ['sprechen', 'aufnahme'],
      });

      expect(exercise.description, 'Tu dies.');
      expect(exercise.equipment, ['Handy']);
      expect(exercise.tags, ['sprechen', 'aufnahme']);
    });

    test('doppelt die Domäne nicht, wenn sie schon Tag ist', () {
      final exercise = Exercise.fromJson({
        'id': 'x',
        'name': 'X',
        'domain': 'geige',
        'tags': ['geige', 'bogen'],
      });
      expect(exercise.tags, ['geige', 'bogen']);
    });

    test('überlebt die Rundreise durch JSON', () {
      final alt = Exercise.fromJson({
        'id': 'alt',
        'name': 'Alte Übung',
        'domain': 'geige',
        'summary': 'Worum es geht.',
        'instructions': ['Schritt eins.'],
        'requirements': ['Metronom'],
        'benefits': ['Wird besser'],
        'tags': ['notation'],
      });
      final neu = Exercise.fromJson(alt.toJson());

      expect(neu.description, alt.description);
      expect(neu.equipment, alt.equipment);
      expect(neu.benefits, alt.benefits);
      expect(neu.tags, alt.tags);
      expect(neu.toJson().containsKey('domain'), isFalse);
    });
  });
}

/// Beim Löschen eines Programms bleiben die Übungen liegen — absichtlich. Wer
/// viel ausprobiert, sammelt dadurch Bestand an, den niemand mehr sieht und
/// der trotzdem im Tag-Pool mitzählt.
void _orphanTests() {
  group('Verwaiste Einträge', () {
    Library mitProgramm() => const Library().merge(
      Bundle(
        exercises: [
          Exercise(id: 'benutzt', name: 'Benutzt', tags: ['geige']),
          Exercise(id: 'verwaist', name: 'Verwaist', tags: ['krafttraining']),
        ],
        routines: [
          Routine(
            id: 'r-benutzt',
            name: 'Einheit',
            slots: [ExerciseSlot(exerciseId: 'benutzt')],
          ),
          Routine(id: 'r-verwaist', name: 'Rest', slots: []),
        ],
        programs: [
          Program(
            id: 'p',
            name: 'Programm',
            phases: [
              Phase(
                id: 'p1',
                name: 'Phase',
                weeks: 1,
                schedule: CycleSchedule(days: [DaySlot(routineId: 'r-benutzt')]),
              ),
            ],
          ),
        ],
      ),
    );

    test('findet, worauf kein Programm zeigt', () {
      final weg = mitProgramm().orphans;
      expect(weg.exercises, {'verwaist'});
      expect(weg.routines, {'r-verwaist'});
    });

    test('räumt nur die Verwaisten weg', () {
      final sauber = mitProgramm().withoutOrphans();
      expect(sauber.exercises.keys, ['benutzt']);
      expect(sauber.routines.keys, ['r-benutzt']);
      expect(sauber.programs, hasLength(1));
    });

    test('und damit auch aus dem Tag-Pool', () {
      final vorher = tagPool(mitProgramm().exercises.values).map((t) => t.tag);
      final nachher = tagPool(
        mitProgramm().withoutOrphans().exercises.values,
      ).map((t) => t.tag);

      expect(vorher, contains('krafttraining'));
      expect(nachher, isNot(contains('krafttraining')));
      expect(nachher, contains('geige'));
    });
  });
}
