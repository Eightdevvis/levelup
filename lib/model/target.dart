/// Wie eine einzelne Ausführung gemessen wird.
///
/// Das ist der Kern der Domänen-Unabhängigkeit: eine Geigenübung wird in
/// Minuten gemessen, ein Klimmzug in Wiederholungen, Gehörtraining in einer
/// Trefferquote und eine Zeichenaufgabe gar nicht. Solange der Player alle
/// vier Varianten kann, bleibt er generisch.
library;

sealed class Target {
  const Target();

  String get kind;

  Map<String, dynamic> toJson();

  /// Kurzform für die UI, z.B. "12 Wdh." oder "16/20 richtig".
  String describe();

  /// Der Zahlenwert, an dem eine Progression ansetzt (null = nicht steigerbar).
  num? get progressionValue;

  /// Kopie mit neuem Progressionswert.
  Target withProgressionValue(num value);

  static Target fromJson(Map<String, dynamic> json) {
    final kind = json['kind'] as String?;
    return switch (kind) {
      'duration' => DurationTarget(seconds: (json['seconds'] as num).round()),
      'reps' => RepsTarget(reps: (json['reps'] as num).round()),
      'quota' => QuotaTarget(
          attempts: (json['attempts'] as num).round(),
          required: (json['required'] as num).round(),
        ),
      'open' => OpenTarget(prompt: json['prompt'] as String?),
      _ => throw FormatException('Unbekannter Target-Typ: $kind'),
    };
  }
}

/// Zeitbasiert — "10 Minuten Tonleitern", "60 Sekunden Plank".
class DurationTarget extends Target {
  const DurationTarget({required this.seconds});

  final int seconds;

  @override
  String get kind => 'duration';

  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'seconds': seconds};

  @override
  String describe() {
    if (seconds < 60) return '$seconds s';
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return rest == 0 ? '$minutes min' : '$minutes:${rest.toString().padLeft(2, '0')} min';
  }

  @override
  num? get progressionValue => seconds;

  @override
  Target withProgressionValue(num value) =>
      DurationTarget(seconds: value.round().clamp(1, 1 << 30));
}

/// Wiederholungsbasiert — "12 Wiederholungen", "8 Takte".
class RepsTarget extends Target {
  const RepsTarget({required this.reps});

  final int reps;

  @override
  String get kind => 'reps';

  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'reps': reps};

  @override
  String describe() => '$reps Wdh.';

  @override
  num? get progressionValue => reps;

  @override
  Target withProgressionValue(num value) =>
      RepsTarget(reps: value.round().clamp(1, 1 << 30));
}

/// Trefferquote — "20 Intervalle hören, 16 müssen sitzen".
///
/// Der Fall, den reine Fitness-Apps nicht abbilden können und der für
/// Gehörtraining, Vokabeln oder Notenlesen der eigentlich richtige ist.
class QuotaTarget extends Target {
  const QuotaTarget({required this.attempts, required this.required});

  final int attempts;
  final int required;

  @override
  String get kind => 'quota';

  @override
  Map<String, dynamic> toJson() =>
      {'kind': kind, 'attempts': attempts, 'required': required};

  @override
  String describe() => '$required/$attempts richtig';

  /// Gesteigert wird die Hürde, nicht die Menge.
  @override
  num? get progressionValue => required;

  @override
  Target withProgressionValue(num value) => QuotaTarget(
        attempts: attempts,
        required: value.round().clamp(1, attempts),
      );

  bool isPassed(int correct) => correct >= required;
}

/// Offen — "eine Skizze", "frei improvisieren". Kein Zielwert, nur erledigt.
class OpenTarget extends Target {
  const OpenTarget({this.prompt});

  final String? prompt;

  @override
  String get kind => 'open';

  @override
  Map<String, dynamic> toJson() =>
      {'kind': kind, if (prompt != null) 'prompt': prompt};

  @override
  String describe() => prompt ?? 'offen';

  @override
  num? get progressionValue => null;

  @override
  Target withProgressionValue(num value) => this;
}

/// Eine Zusatzgröße neben dem Ziel: 20 kg, 60 bpm, 80 %.
///
/// Bewusst numerisch statt als Freitext, damit Progression darauf laufen kann —
/// "jede Woche 4 bpm schneller" ist beim Üben genauso normal wie
/// "jede Woche 2,5 kg mehr" beim Training.
class Load {
  const Load({required this.value, required this.unit});

  final double value;
  final String unit;

  Map<String, dynamic> toJson() => {'value': value, 'unit': unit};

  static Load fromJson(Map<String, dynamic> json) => Load(
        value: (json['value'] as num).toDouble(),
        unit: json['unit'] as String,
      );

  String describe() {
    final rounded = value == value.roundToDouble()
        ? value.round().toString()
        : value.toStringAsFixed(1);
    return '$rounded $unit';
  }

  Load withValue(double next) => Load(value: next, unit: unit);
}
