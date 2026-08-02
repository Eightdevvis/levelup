import 'package:flutter_test/flutter_test.dart';
import 'package:programs/data/chat_prompts.dart';
import 'package:programs/data/plan_round.dart';
import 'package:programs/data/tag_round.dart';
import 'package:programs/model/exercise.dart';
import 'package:programs/model/program.dart';

/// Der kostenlose Weg in zwei Runden.
///
/// Geprüft wird vor allem, was eine KI-Antwort in freier Wildbahn anrichtet:
/// Code-Zäune, „hier bitteschön"-Vorreden, einfache statt doppelter
/// Anführungszeichen, Schlüssel ohne Anführungszeichen. Wer das dem Nutzer
/// zum Wegschneiden überlässt, bekommt Fehlerberichte über den Parser.

Exercise ex(String id, String name, List<String> tags, {String? domain}) {
  return Exercise(
    id: id,
    name: name,
    domain: domain ?? tags.first,
    summary: 'Zusammenfassung zu $name',
    instructions: ['Mach $name.'],
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
     "domain": "geige",
     "summary": "Lange Striche vor dem Spiegel.",
     "instructions": ["Stell dich seitlich vor den Spiegel.", "Spiel lange Striche."],
     "benefits": ["Du siehst die Abweichung"],
     "requirements": ["Spiegel"],
     "tags": ["geige", "bogen", "haltung"]
   }
''');
      expect(result.problems, isEmpty);
      final draft = result.requests.single as DraftRequest;
      expect(draft.exercise.name, 'Bogen im Spiegel führen');
      expect(draft.exercise.id, 'geige-bogen-im-spiegel-fuehren');
      expect(draft.exercise.instructions, hasLength(2));
      expect(draft.exercise.requirements, ['Spiegel']);
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
      // "description" ist der Name aus der Anleitung, "summary" der des
      // Datenmodells. Beides muss ankommen.
      expect(draft.exercise.summary, 'Stimme nach Gehör, prüfe danach.');
      expect(draft.exercise.instructions, isNotEmpty);
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
