import 'set_spec.dart';

/// Woran eine Steigerung ansetzt.
enum ProgressionField {
  /// Am Ziel selbst: mehr Wiederholungen, längere Dauer, höhere Trefferquote.
  target,

  /// An der Zusatzgröße: mehr Gewicht, höheres Tempo.
  load,
}

ProgressionField _fieldFromString(String? value) => switch (value) {
  'load' => ProgressionField.load,
  _ => ProgressionField.target,
};

/// Wie sich eine Übung über die Wochen einer Phase verändert.
///
/// Das ist die Ebene, die reine Routine-Apps nicht haben: dort ist ein Schritt
/// in Woche 6 exakt derselbe wie in Woche 1.
sealed class Progression {
  const Progression();

  String get kind;

  Map<String, dynamic> toJson();

  /// Beschreibung für die Programm-Übersicht.
  String describe();

  /// Wendet die Regel auf den Ausgangswert an. [weekIndex] ist 0-basiert
  /// und zählt innerhalb der Phase, nicht über das ganze Programm.
  SetSpec apply(SetSpec base, int weekIndex);

  static Progression fromJson(Map<String, dynamic>? json) {
    if (json == null) return const NoProgression();
    final kind = json['kind'] as String?;
    return switch (kind) {
      'none' => const NoProgression(),
      'linear' => LinearProgression(
        field: _fieldFromString(json['field'] as String?),
        amount: (json['amount'] as num).toDouble(),
        everyWeeks: (json['everyWeeks'] as num?)?.round() ?? 1,
        cap: (json['cap'] as num?)?.toDouble(),
      ),
      'table' => TableProgression(
        perWeek: (json['perWeek'] as List<dynamic>)
            .map(
              (e) => e == null
                  ? null
                  : SetSpec.fromJson(e as Map<String, dynamic>),
            )
            .toList(growable: false),
      ),
      _ => throw FormatException('Unbekannter Progressions-Typ: $kind'),
    };
  }
}

/// Jede Woche gleich.
class NoProgression extends Progression {
  const NoProgression();

  @override
  String get kind => 'none';

  @override
  Map<String, dynamic> toJson() => {'kind': kind};

  @override
  String describe() => 'gleichbleibend';

  @override
  SetSpec apply(SetSpec base, int weekIndex) => base;
}

/// Gleichmäßige Steigerung: "+2 Wdh. pro Woche", "+4 bpm alle 2 Wochen".
class LinearProgression extends Progression {
  const LinearProgression({
    required this.field,
    required this.amount,
    this.everyWeeks = 1,
    this.cap,
  });

  final ProgressionField field;
  final double amount;

  /// Steigerung greift nur alle n Wochen — erlaubt langsame Rampen.
  final int everyWeeks;

  /// Obergrenze, damit eine lange Phase nicht ins Absurde läuft.
  final double? cap;

  @override
  String get kind => 'linear';

  @override
  Map<String, dynamic> toJson() => {
    'kind': kind,
    'field': field.name,
    'amount': amount,
    'everyWeeks': everyWeeks,
    if (cap != null) 'cap': cap,
  };

  @override
  String describe() {
    final sign = amount >= 0 ? '+' : '';
    final rhythm = everyWeeks == 1 ? 'pro Woche' : 'alle $everyWeeks Wochen';
    final what = field == ProgressionField.load ? 'Last' : 'Ziel';
    return '$what $sign${_trim(amount)} $rhythm';
  }

  @override
  SetSpec apply(SetSpec base, int weekIndex) {
    final steps = everyWeeks <= 1 ? weekIndex : weekIndex ~/ everyWeeks;
    if (steps <= 0) return base;
    final delta = amount * steps;

    switch (field) {
      case ProgressionField.target:
        final current = base.target.progressionValue;
        if (current == null) return base;
        final next = _capped(current + delta);
        return base.copyWith(target: base.target.withProgressionValue(next));
      case ProgressionField.load:
        final load = base.load;
        if (load == null) return base;
        final next = _capped(load.value + delta);
        return base.copyWith(load: load.withValue(next.toDouble()));
    }
  }

  num _capped(num value) {
    final limit = cap;
    if (limit == null) return value;
    return amount >= 0
        ? (value > limit ? limit : value)
        : (value < limit ? limit : value);
  }

  static String _trim(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
}

/// Explizite Werte pro Woche — inklusive Deload-Wochen und Sprüngen.
///
/// Die für AI-generierte Pläne robusteste Form: das Modell schreibt einfach
/// hin, was in Woche 1..n stehen soll, statt eine Formel zu erfinden.
class TableProgression extends Progression {
  const TableProgression({required this.perWeek});

  /// Index = Woche innerhalb der Phase. `null` bedeutet "unverändert".
  /// Ist die Phase länger als die Tabelle, gilt der letzte Eintrag weiter.
  final List<SetSpec?> perWeek;

  @override
  String get kind => 'table';

  @override
  Map<String, dynamic> toJson() => {
    'kind': kind,
    'perWeek': perWeek.map((e) => e?.toJson()).toList(),
  };

  @override
  String describe() => 'Wochenplan (${perWeek.length} Wochen)';

  @override
  SetSpec apply(SetSpec base, int weekIndex) {
    if (perWeek.isEmpty) return base;
    final index = weekIndex < perWeek.length ? weekIndex : perWeek.length - 1;
    for (var i = index; i >= 0; i--) {
      final entry = perWeek[i];
      if (entry != null) return entry;
    }
    return base;
  }
}
