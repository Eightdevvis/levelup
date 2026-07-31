import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:programs/model/library.dart';
import 'package:programs/model/patch.dart';

/// Geprüft wird gegen den echten Plan vom Server, nicht gegen ein
/// zurechtgelegtes Beispiel: ein Patch muss auf dem funktionieren, was
/// tatsächlich ankommt.
void main() {
  late Bundle plan;
  late String routineId;
  late String exerciseId;

  setUp(() {
    plan = Bundle.fromJson(
      jsonDecode(File('test/fixtures/live_plan.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    routineId = plan.routines.first.id;
    exerciseId = plan.routines.first.slots.first.exerciseId;
  });

  PlanPatch patchOf(List<Map<String, dynamic>> ops, {String? note}) =>
      PlanPatch.fromJson({
        'version': 1,
        'personalNote': ?note,
        'exercises': const [],
        'operations': ops,
      });

  int slotsWith(Bundle bundle, String id) => bundle.routines.fold(
    0,
    (sum, r) => sum + r.slots.where((s) => s.exerciseId == id).length,
  );

  group('Bausteine tauschen und entfernen', () {
    test('entfernen nimmt den Baustein aus allen Listen', () {
      final vorher = slotsWith(plan, exerciseId);
      expect(vorher, greaterThan(0));

      final result = applyPatch(
        plan,
        patchOf([
          {'op': 'removeExercise', 'exerciseId': exerciseId},
        ]),
      );

      expect(slotsWith(result.bundle, exerciseId), 0);
      expect(result.skipped, isEmpty);
    });

    test('mit routineId bleibt der Rest unangetastet', () {
      // Ein Baustein, der in mehr als einer Liste steht — sonst prüft der
      // Test nichts.
      final mehrfach = plan.exercises
          .map((e) => e.id)
          .where(
            (id) => plan.routines.where(
              (r) => r.slots.any((s) => s.exerciseId == id),
            ).length > 1,
          )
          .toList();
      if (mehrfach.isEmpty) return; // im Zweifel nichts behaupten

      final id = mehrfach.first;
      final ziel = plan.routines.firstWhere(
        (r) => r.slots.any((s) => s.exerciseId == id),
      );
      final vorher = slotsWith(plan, id);

      final result = applyPatch(
        plan,
        patchOf([
          {'op': 'removeExercise', 'exerciseId': id, 'routineId': ziel.id},
        ]),
      );

      expect(slotsWith(result.bundle, id), lessThan(vorher));
      expect(slotsWith(result.bundle, id), greaterThan(0));
    });

    test('tauschen braucht den neuen Baustein im Patch', () {
      final result = applyPatch(
        plan,
        PlanPatch.fromJson({
          'operations': [
            {
              'op': 'replaceExercise',
              'oldExerciseId': exerciseId,
              'newExerciseId': 'gibt-es-nicht',
            },
          ],
        }),
      );

      // Nichts passiert, aber es wird gesagt.
      expect(slotsWith(result.bundle, exerciseId), slotsWith(plan, exerciseId));
      expect(result.skipped.single, contains('gibt-es-nicht'));
    });

    test('tauschen ersetzt und räumt den alten Baustein weg', () {
      final result = applyPatch(
        plan,
        PlanPatch.fromJson({
          'exercises': [
            {
              'id': 'test-neuer-baustein',
              'name': 'Neuer Baustein',
              'domain': 'test',
              'summary': 'Ersetzt den alten.',
            },
          ],
          'operations': [
            {
              'op': 'replaceExercise',
              'oldExerciseId': exerciseId,
              'newExerciseId': 'test-neuer-baustein',
            },
          ],
        }),
      );

      expect(slotsWith(result.bundle, 'test-neuer-baustein'), greaterThan(0));
      expect(slotsWith(result.bundle, exerciseId), 0);
      expect(result.skipped, isEmpty);

      // Der alte Baustein wird nicht mehr gebraucht und fliegt aus dem Bundle.
      expect(result.bundle.exercises.map((e) => e.id), isNot(contains(exerciseId)));
      expect(
        result.bundle.exercises.map((e) => e.id),
        contains('test-neuer-baustein'),
      );
    });
  });

  group('Zahlen und Texte', () {
    test('Phasenlänge ändern', () {
      final phase = plan.programs.single.phases.first;
      final result = applyPatch(
        plan,
        patchOf([
          {'op': 'setPhaseWeeks', 'phaseId': phase.id, 'weeks': phase.weeks + 2},
        ]),
      );

      expect(
        result.bundle.programs.single.phases.first.weeks,
        phase.weeks + 2,
      );
    });

    test('Begründung ändern lässt den Rest in Ruhe', () {
      final result = applyPatch(
        plan,
        patchOf([
          {'op': 'setProgramText', 'field': 'rationale', 'text': 'Neu gedacht.'},
        ]),
      );

      final nachher = result.bundle.programs.single;
      expect(nachher.rationale, 'Neu gedacht.');
      expect(nachher.name, plan.programs.single.name);
      expect(nachher.phases.length, plan.programs.single.phases.length);
    });

    test('Sätze ändern trifft nur den gemeinten Slot', () {
      final result = applyPatch(
        plan,
        patchOf([
          {
            'op': 'setSets',
            'routineId': routineId,
            'exerciseId': exerciseId,
            'sets': [
              {
                'target': {'kind': 'duration', 'seconds': 999},
              },
            ],
          },
        ]),
      );

      final routine = result.bundle.routines.firstWhere(
        (r) => r.id == routineId,
      );
      final slot = routine.slots.firstWhere((s) => s.exerciseId == exerciseId);
      expect(slot.sets.single.target.toJson()['seconds'], 999);
      expect(result.skipped, isEmpty);
    });
  });

  group('Robustheit', () {
    test('eine Operation ins Leere wird gemeldet, nicht verschluckt', () {
      final result = applyPatch(
        plan,
        patchOf([
          {'op': 'setPhaseWeeks', 'phaseId': 'gibt-es-nicht', 'weeks': 3},
        ]),
      );

      expect(result.skipped, hasLength(1));
      expect(result.bundle.programs.single.phases.first.weeks,
          plan.programs.single.phases.first.weeks);
    });

    test('eine unlesbare Operation reißt die anderen nicht mit', () {
      final result = applyPatch(
        plan,
        patchOf([
          {'op': 'voelligUnbekannt', 'irgendwas': 1},
          {'op': 'setProgramText', 'field': 'name', 'text': 'Trotzdem da'},
        ]),
      );

      expect(result.bundle.programs.single.name, 'Trotzdem da');
    });

    test('ein leerer Patch lässt den Plan, wie er ist', () {
      final result = applyPatch(plan, patchOf(const []));

      expect(result.skipped, isEmpty);
      expect(
        jsonEncode(result.bundle.toJson()),
        jsonEncode(plan.toJson()),
      );
    });

    test('die persönliche Nachricht wird ersetzt, nicht angehängt', () {
      final result = applyPatch(
        plan,
        patchOf(const [], note: 'Ich habe die eine Übung getauscht.'),
      );

      expect(result.bundle.personalNote, 'Ich habe die eine Übung getauscht.');
    });
  });
}
