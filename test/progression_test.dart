import 'package:flutter_test/flutter_test.dart';
import 'package:programs/model/progression.dart';
import 'package:programs/model/set_spec.dart';
import 'package:programs/model/target.dart';

void main() {
  group('LinearProgression auf das Ziel', () {
    const base = SetSpec(target: RepsTarget(reps: 10));

    test('Woche 0 bleibt unverändert', () {
      const rule = LinearProgression(field: ProgressionField.target, amount: 2);
      final result = rule.apply(base, 0);
      expect((result.target as RepsTarget).reps, 10);
    });

    test('steigert pro Woche', () {
      const rule = LinearProgression(field: ProgressionField.target, amount: 2);
      expect((rule.apply(base, 1).target as RepsTarget).reps, 12);
      expect((rule.apply(base, 3).target as RepsTarget).reps, 16);
    });

    test('everyWeeks bremst die Steigerung', () {
      const rule = LinearProgression(
        field: ProgressionField.target,
        amount: 1,
        everyWeeks: 2,
      );
      expect((rule.apply(base, 1).target as RepsTarget).reps, 10);
      expect((rule.apply(base, 2).target as RepsTarget).reps, 11);
      expect((rule.apply(base, 5).target as RepsTarget).reps, 12);
    });

    test('cap begrenzt nach oben', () {
      const rule = LinearProgression(
        field: ProgressionField.target,
        amount: 5,
        cap: 20,
      );
      expect((rule.apply(base, 10).target as RepsTarget).reps, 20);
    });

    test('negative Steigerung wird durch cap nach unten begrenzt', () {
      const rule = LinearProgression(
        field: ProgressionField.target,
        amount: -2,
        cap: 6,
      );
      expect((rule.apply(base, 1).target as RepsTarget).reps, 8);
      expect((rule.apply(base, 10).target as RepsTarget).reps, 6);
    });
  });

  group('LinearProgression auf die Last', () {
    const base = SetSpec(
      target: RepsTarget(reps: 8),
      load: Load(value: 40, unit: 'kg'),
    );

    test('steigert das Gewicht, nicht die Wiederholungen', () {
      const rule = LinearProgression(
        field: ProgressionField.load,
        amount: 2.5,
      );
      final week4 = rule.apply(base, 4);
      expect(week4.load!.value, 50);
      expect((week4.target as RepsTarget).reps, 8);
    });

    test('ohne Last passiert nichts', () {
      const rule = LinearProgression(field: ProgressionField.load, amount: 5);
      const noLoad = SetSpec(target: RepsTarget(reps: 8));
      expect(rule.apply(noLoad, 3).load, isNull);
    });
  });

  group('Quoten-Ziel', () {
    test('Steigerung erhöht die nötigen Treffer, nicht die Versuche', () {
      const base = SetSpec(target: QuotaTarget(attempts: 20, required: 13));
      const rule = LinearProgression(field: ProgressionField.target, amount: 1);
      final week4 = rule.apply(base, 4).target as QuotaTarget;
      expect(week4.required, 17);
      expect(week4.attempts, 20);
    });

    test('nötige Treffer können die Versuche nicht übersteigen', () {
      const base = SetSpec(target: QuotaTarget(attempts: 20, required: 18));
      const rule = LinearProgression(field: ProgressionField.target, amount: 5);
      final late = rule.apply(base, 10).target as QuotaTarget;
      expect(late.required, 20);
    });

    test('isPassed prüft gegen die Hürde', () {
      const target = QuotaTarget(attempts: 20, required: 16);
      expect(target.isPassed(16), isTrue);
      expect(target.isPassed(15), isFalse);
    });
  });

  group('Offenes Ziel', () {
    test('bleibt von Progression unberührt', () {
      const base = SetSpec(target: OpenTarget(prompt: 'eine Skizze'));
      const rule = LinearProgression(field: ProgressionField.target, amount: 5);
      expect(rule.apply(base, 8).target, isA<OpenTarget>());
    });
  });

  group('TableProgression', () {
    test('nimmt den Eintrag der jeweiligen Woche', () {
      const rule = TableProgression(perWeek: [
        SetSpec(target: RepsTarget(reps: 5)),
        SetSpec(target: RepsTarget(reps: 8)),
        SetSpec(target: RepsTarget(reps: 3)), // Deload
      ]);
      const base = SetSpec(target: RepsTarget(reps: 99));
      expect((rule.apply(base, 0).target as RepsTarget).reps, 5);
      expect((rule.apply(base, 1).target as RepsTarget).reps, 8);
      expect((rule.apply(base, 2).target as RepsTarget).reps, 3);
    });

    test('hält den letzten Eintrag, wenn die Phase länger ist', () {
      const rule = TableProgression(perWeek: [
        SetSpec(target: RepsTarget(reps: 5)),
        SetSpec(target: RepsTarget(reps: 8)),
      ]);
      const base = SetSpec(target: RepsTarget(reps: 99));
      expect((rule.apply(base, 7).target as RepsTarget).reps, 8);
    });

    test('null bedeutet "wie in der Woche davor"', () {
      const rule = TableProgression(perWeek: [
        SetSpec(target: RepsTarget(reps: 5)),
        null,
        SetSpec(target: RepsTarget(reps: 9)),
      ]);
      const base = SetSpec(target: RepsTarget(reps: 99));
      expect((rule.apply(base, 1).target as RepsTarget).reps, 5);
      expect((rule.apply(base, 2).target as RepsTarget).reps, 9);
    });
  });

  group('JSON', () {
    test('Progressionen überleben eine Runde', () {
      const rule = LinearProgression(
        field: ProgressionField.load,
        amount: 2.5,
        everyWeeks: 2,
        cap: 100,
      );
      final restored = Progression.fromJson(rule.toJson()) as LinearProgression;
      expect(restored.field, ProgressionField.load);
      expect(restored.amount, 2.5);
      expect(restored.everyWeeks, 2);
      expect(restored.cap, 100);
    });

    test('fehlende Progression wird zu NoProgression', () {
      expect(Progression.fromJson(null), isA<NoProgression>());
    });

    test('alle Ziel-Typen überleben eine Runde', () {
      const targets = <Target>[
        DurationTarget(seconds: 300),
        RepsTarget(reps: 12),
        QuotaTarget(attempts: 20, required: 16),
        OpenTarget(prompt: 'frei'),
      ];
      for (final target in targets) {
        final restored = Target.fromJson(target.toJson());
        expect(restored.kind, target.kind);
        expect(restored.describe(), target.describe());
      }
    });
  });
}
