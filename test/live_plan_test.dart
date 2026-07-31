import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:programs/engine/resolver.dart';
import 'package:programs/model/library.dart';
import 'package:programs/model/target.dart';

/// Ein Plan, wie ihn der Server wirklich ausgegeben hat — nicht ausgedacht,
/// sondern am 31.07.2026 über `/v1/generate` erzeugt und unverändert abgelegt.
///
/// Der Zweck: die Kette Modell → JSON → App bricht sonst still. Ein
/// selbstgeschriebenes Beispiel prüft nur, ob der Parser zu dem passt, was ich
/// mir vorgestellt habe. Dieses hier prüft, ob er zu dem passt, was tatsächlich
/// ankommt.
void main() {
  late Bundle bundle;

  setUpAll(() {
    final raw = File('test/fixtures/live_plan.json').readAsStringSync();
    bundle = Bundle.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  });

  test('lässt sich vollständig einlesen', () {
    expect(bundle.programs, hasLength(1));
    expect(bundle.exercises, isNotEmpty);
    expect(bundle.routines, isNotEmpty);
  });

  test('enthält keine toten Verweise', () {
    final library = const Library().merge(bundle);
    expect(library.missingReferences(bundle.programs.single.id), isEmpty);
  });

  test('jeder Tag der Laufzeit löst sich auf', () {
    final library = const Library().merge(bundle);
    final program = bundle.programs.single;
    final wochen = program.phases.fold<int>(0, (sum, p) => sum + p.weeks);

    final resolver = ProgramResolver(library);
    for (var tag = 0; tag < wochen * 7; tag++) {
      expect(
        resolver.resolveDay(program, tag),
        isNotNull,
        reason: 'Tag $tag ließ sich nicht auflösen',
      );
    }
  });

  test('nutzt mehr als nur Dauer und Wiederholungen', () {
    final ziele = <String>{};
    for (final routine in bundle.routines) {
      for (final slot in routine.slots) {
        for (final set in slot.sets) {
          ziele.add(switch (set.target) {
            DurationTarget() => 'duration',
            RepsTarget() => 'reps',
            QuotaTarget() => 'quota',
            OpenTarget() => 'open',
          });
        }
      }
    }
    // Genau das kann eine Workout-App nicht: eine Trefferquote und eine
    // offene Aufgabe im selben Plan.
    expect(ziele, containsAll(['quota', 'open']));
  });
}
