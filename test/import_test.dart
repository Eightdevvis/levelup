import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:programs/data/seed.dart';
import 'package:programs/data/storage.dart';
import 'package:programs/model/library.dart';
import 'package:programs/model/target.dart';
import 'package:programs/state/app_state.dart';

const _minimalPlan = '''
{
  "version": 1,
  "exercises": [
    {
      "id": "x-1",
      "name": "Testübung",
      "domain": "test",
      "instructions": ["Erstens", "Zweitens"],
      "benefits": ["Wird besser"]
    }
  ],
  "routines": [
    {
      "id": "x-r",
      "name": "Testliste",
      "slots": [
        {
          "exerciseId": "x-1",
          "sets": [{"target": {"kind": "quota", "attempts": 20, "required": 14}}],
          "progression": {"kind": "linear", "field": "target", "amount": 1, "cap": 19}
        }
      ]
    }
  ],
  "programs": [
    {
      "id": "x-p",
      "name": "Testprogramm",
      "domain": "test",
      "rationale": "Weil.",
      "phases": [
        {
          "id": "x-ph",
          "name": "Phase",
          "weeks": 4,
          "schedule": {"kind": "everyDay", "routineId": "x-r", "daysPerWeek": 7}
        }
      ]
    }
  ]
}
''';

Future<AppState> _freshState() async {
  final state = AppState(Store(MemoryStorageBackend()), seed: seedBundle());
  await state.init();
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Import', () {
    test('legt Übungen, Listen und Programm an', () async {
      final state = await _freshState();
      final before = state.library.exercises.length;

      final result = await state.importJson(_minimalPlan);

      expect(result.ok, isTrue);
      expect(result.warnings, isEmpty);
      expect(state.library.exercises.length, before + 1);
      expect(state.library.program('x-p'), isNotNull);
      expect(state.library.routine('x-r'), isNotNull);
    });

    test('verträgt Code-Zäune aus einem Chat', () async {
      final state = await _freshState();
      final result = await state.importJson('```json\n$_minimalPlan\n```');
      expect(result.ok, isTrue);
      expect(state.library.program('x-p'), isNotNull);
    });

    test('meldet kaputtes JSON, statt zu werfen', () async {
      final state = await _freshState();
      final result = await state.importJson('{ das ist kein json ');
      expect(result.ok, isFalse);
      expect(result.message, contains('JSON'));
    });

    test('lehnt leere Eingabe ab', () async {
      final state = await _freshState();
      expect((await state.importJson('   ')).ok, isFalse);
    });

    test('nennt fehlende Verweise, importiert aber trotzdem', () async {
      final state = await _freshState();
      final broken = jsonDecode(_minimalPlan) as Map<String, dynamic>;
      broken['exercises'] = <dynamic>[]; // Übung weglassen

      final result = await state.importJson(jsonEncode(broken));

      expect(result.ok, isTrue);
      expect(result.warnings, isNotEmpty);
      expect(result.warnings.first, contains('x-1'));
      expect(state.library.program('x-p'), isNotNull);
    });

    test('erneuter Import ersetzt, statt zu doppeln', () async {
      final state = await _freshState();
      await state.importJson(_minimalPlan);
      final count = state.library.programs.length;

      final again = jsonDecode(_minimalPlan) as Map<String, dynamic>;
      (again['programs'] as List<dynamic>).first['name'] = 'Neuer Name';
      await state.importJson(jsonEncode(again));

      expect(state.library.programs.length, count);
      expect(state.library.program('x-p')!.name, 'Neuer Name');
    });

    test('lehnt ein Bundle aus der Zukunft ab', () async {
      final state = await _freshState();
      final future = jsonDecode(_minimalPlan) as Map<String, dynamic>;
      future['version'] = kBundleVersion + 1;

      final result = await state.importJson(jsonEncode(future));
      expect(result.ok, isFalse);
    });
  });

  group('Export', () {
    test('enthält alles, was das Programm braucht', () async {
      final state = await _freshState();
      await state.importJson(_minimalPlan);

      final exported = state.exportProgram('x-p');
      final bundle = Bundle.fromJson(
        jsonDecode(exported) as Map<String, dynamic>,
      );

      expect(bundle.programs.single.id, 'x-p');
      expect(bundle.routines.single.id, 'x-r');
      expect(bundle.exercises.single.id, 'x-1');
    });

    test('Export und Reimport ergeben dasselbe Programm', () async {
      final source = await _freshState();
      final exported = source.exportProgram('p-bach-lesen');

      final target = AppState(
        Store(MemoryStorageBackend()),
        seed: seedBundle(),
      );
      await target.init();
      final result = await target.importJson(exported);

      expect(result.ok, isTrue);
      expect(target.library.missingReferences('p-bach-lesen'), isEmpty);

      final original = source.library.program('p-bach-lesen')!;
      final restored = target.library.program('p-bach-lesen')!;
      expect(restored.totalDays, original.totalDays);
      expect(restored.phases.length, original.phases.length);
      expect(restored.rationale, original.rationale);
    });
  });

  group('Bundle-Rundreise', () {
    test('Seed übersteht JSON in beide Richtungen', () {
      final original = seedBundle();
      final restored = Bundle.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(restored.exercises.length, original.exercises.length);
      expect(restored.routines.length, original.routines.length);
      expect(restored.programs.length, original.programs.length);
    });

    test('Lasten und Ziele behalten ihre Werte', () {
      final restored = Bundle.fromJson(
        jsonDecode(jsonEncode(seedBundle().toJson())) as Map<String, dynamic>,
      );
      final routine = restored.routines.firstWhere((r) => r.id == 'k-r-a');
      final firstSet = routine.slots.first.sets.first;

      expect(firstSet.load!.value, 40);
      expect(firstSet.load!.unit, 'kg');
      expect((firstSet.target as RepsTarget).reps, 8);
    });
  });

  group('Fortschritt', () {
    test('Tag abschließen rückt den Zeiger vor und wird gespeichert', () async {
      final backend = MemoryStorageBackend();
      final state = AppState(Store(backend), seed: seedBundle());
      await state.init();

      await state.startProgram('p-gehoer');
      await state.completeDay('p-gehoer', 0);

      final progress = state.progressFor('p-gehoer');
      expect(progress.currentDay, 1);
      expect(progress.isDayComplete(0), isTrue);
      expect(state.sessions, hasLength(1));

      // Neu geladen aus demselben Speicher — der Fortschritt muss überleben.
      final reloaded = AppState(Store(backend), seed: seedBundle());
      await reloaded.init();
      expect(reloaded.progressFor('p-gehoer').currentDay, 1);
      expect(reloaded.sessions, hasLength(1));
    });

    test('derselbe Tag zweimal erzeugt keine doppelten Einträge', () async {
      final state = await _freshState();
      await state.startProgram('p-gehoer');
      await state.completeDay('p-gehoer', 0);
      await state.completeDay('p-gehoer', 0);
      expect(state.sessions, hasLength(1));
    });

    test('Zurücksetzen entfernt Fortschritt, behält das Programm', () async {
      final state = await _freshState();
      await state.startProgram('p-gehoer');
      await state.completeDay('p-gehoer', 0);
      await state.resetProgram('p-gehoer');

      expect(state.hasStarted('p-gehoer'), isFalse);
      expect(state.sessions, isEmpty);
      expect(state.library.program('p-gehoer'), isNotNull);
    });

    test('Löschen entfernt das Programm, behält die Übungen', () async {
      final state = await _freshState();
      final exerciseCount = state.library.exercises.length;

      await state.deleteProgram('p-gehoer');

      expect(state.library.program('p-gehoer'), isNull);
      expect(state.library.exercises.length, exerciseCount);
    });
  });

  group('Startzustand', () {
    test('ohne seed bleibt die Bibliothek leer — so startet die App', () async {
      final state = AppState(Store(MemoryStorageBackend()));
      await state.init();

      expect(state.library.isEmpty, isTrue);
      expect(state.programs, isEmpty);
      expect(state.isLoading, isFalse);
    });

    test('ein Bundle lässt sich nachträglich installieren', () async {
      final state = AppState(Store(MemoryStorageBackend()));
      await state.init();
      expect(state.programs, isEmpty);

      await state.installBundle(seedBundle());

      expect(state.programs, isNotEmpty);
      expect(state.library.program('p-bach-lesen'), isNotNull);
    });

    test('erste Nutzung füllt die Bibliothek mit den Seed-Inhalten', () async {
      final state = await _freshState();
      expect(state.library.programs, isNotEmpty);
      expect(state.isLoading, isFalse);
    });

    test('vorhandener Speicher wird nicht mit Seeds überschrieben', () async {
      final backend = MemoryStorageBackend();
      final first = AppState(Store(backend), seed: seedBundle());
      await first.init();
      await first.deleteProgram('p-gehoer');

      final second = AppState(Store(backend), seed: seedBundle());
      await second.init();
      expect(second.library.program('p-gehoer'), isNull);
    });
  });
}
