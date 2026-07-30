import 'progression.dart';
import 'set_spec.dart';

/// Eine Übung im Kontext einer Liste: mit ihren Sätzen, ihrer Pause und
/// ihrer Steigerung über die Wochen.
///
/// Die Trennung ist wichtig: die [Exercise] beschreibt *was* man tut und ist
/// überall wiederverwendbar, der Slot beschreibt *wie viel davon hier*.
class ExerciseSlot {
  const ExerciseSlot({
    required this.exerciseId,
    this.sets = const [],
    this.restSeconds = 0,
    this.note,
    this.progression = const NoProgression(),
    this.optional = false,
  });

  final String exerciseId;
  final List<SetSpec> sets;

  /// Pause nach jedem Satz.
  final int restSeconds;

  /// Programmspezifischer Hinweis, überschreibt nichts an der Übung selbst.
  final String? note;

  final Progression progression;

  /// Kür statt Pflicht — darf im Player übersprungen werden, ohne dass der
  /// Tag als unvollständig gilt.
  final bool optional;

  /// Die Sätze, wie sie in Woche [weekInPhase] (0-basiert) gelten.
  List<SetSpec> setsForWeek(int weekInPhase) =>
      sets.map((s) => progression.apply(s, weekInPhase)).toList(growable: false);

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'sets': sets.map((e) => e.toJson()).toList(),
        if (restSeconds > 0) 'restSeconds': restSeconds,
        if (note != null) 'note': note,
        if (progression is! NoProgression) 'progression': progression.toJson(),
        if (optional) 'optional': true,
      };

  static ExerciseSlot fromJson(Map<String, dynamic> json) => ExerciseSlot(
        exerciseId: json['exerciseId'] as String,
        sets: (json['sets'] as List<dynamic>? ?? const [])
            .map((e) => SetSpec.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        restSeconds: (json['restSeconds'] as num?)?.round() ?? 0,
        note: json['note'] as String?,
        progression:
            Progression.fromJson(json['progression'] as Map<String, dynamic>?),
        optional: json['optional'] as bool? ?? false,
      );
}

/// Die "Liste" — eine geordnete Folge von Übungen, die als Einheit
/// abgespielt wird. Bibliotheks-Objekt, damit dieselbe Liste in mehreren
/// Programmen und an mehreren Tagen auftauchen kann.
class Routine {
  const Routine({
    required this.id,
    required this.name,
    this.description,
    this.slots = const [],
  });

  final String id;
  final String name;
  final String? description;
  final List<ExerciseSlot> slots;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (description != null) 'description': description,
        'slots': slots.map((e) => e.toJson()).toList(),
      };

  static Routine fromJson(Map<String, dynamic> json) => Routine(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        slots: (json['slots'] as List<dynamic>? ?? const [])
            .map((e) => ExerciseSlot.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

/// Ein Tag im Zyklus: entweder eine Liste oder Pause.
class DaySlot {
  const DaySlot({this.routineId, this.label});

  factory DaySlot.rest([String? label]) => DaySlot(label: label ?? 'Pause');

  final String? routineId;
  final String? label;

  bool get isRest => routineId == null;

  Map<String, dynamic> toJson() => {
        if (routineId != null) 'routineId': routineId,
        if (label != null) 'label': label,
      };

  static DaySlot fromJson(Map<String, dynamic> json) => DaySlot(
        routineId: json['routineId'] as String?,
        label: json['label'] as String?,
      );
}

/// Wie Listen auf Tage gelegt werden.
sealed class Schedule {
  const Schedule();

  String get kind;

  /// Wie viele Tage bis sich der Plan wiederholt. Definiert zugleich, wie
  /// viele Tage eine "Woche" dieses Programms hat.
  int get cycleLength;

  DaySlot slotForDay(int dayInCycle);

  Map<String, dynamic> toJson();

  /// Alle Listen, die dieser Plan überhaupt anfasst.
  Set<String> get routineIds;

  static Schedule fromJson(Map<String, dynamic> json) {
    final kind = json['kind'] as String?;
    return switch (kind) {
      'everyDay' => EveryDaySchedule(
          routineId: json['routineId'] as String,
          daysPerWeek: (json['daysPerWeek'] as num?)?.round() ?? 7,
        ),
      'cycle' => CycleSchedule(
          days: (json['days'] as List<dynamic>)
              .map((e) => DaySlot.fromJson(e as Map<String, dynamic>))
              .toList(growable: false),
        ),
      _ => throw FormatException('Unbekannter Schedule-Typ: $kind'),
    };
  }
}

/// Der einfache Fall: eine Liste, jeden Tag dieselbe.
class EveryDaySchedule extends Schedule {
  const EveryDaySchedule({required this.routineId, this.daysPerWeek = 7});

  final String routineId;
  final int daysPerWeek;

  @override
  String get kind => 'everyDay';

  @override
  int get cycleLength => daysPerWeek;

  @override
  DaySlot slotForDay(int dayInCycle) => DaySlot(routineId: routineId);

  @override
  Set<String> get routineIds => {routineId};

  @override
  Map<String, dynamic> toJson() =>
      {'kind': kind, 'routineId': routineId, 'daysPerWeek': daysPerWeek};
}

/// Der allgemeine Fall: ein Zyklus aus n Tagen, die sich wiederholen.
/// Mit 7 Einträgen ist das eine klassische Woche inklusive Pausentagen,
/// mit 3 Einträgen eine A/B/C-Rotation.
class CycleSchedule extends Schedule {
  const CycleSchedule({required this.days});

  final List<DaySlot> days;

  @override
  String get kind => 'cycle';

  @override
  int get cycleLength => days.isEmpty ? 1 : days.length;

  @override
  DaySlot slotForDay(int dayInCycle) {
    if (days.isEmpty) return DaySlot.rest();
    return days[dayInCycle % days.length];
  }

  @override
  Set<String> get routineIds =>
      days.map((d) => d.routineId).whereType<String>().toSet();

  @override
  Map<String, dynamic> toJson() =>
      {'kind': kind, 'days': days.map((e) => e.toJson()).toList()};
}

/// Ein Abschnitt des Programms mit eigenem Charakter und eigener Länge —
/// "Grundlagen", "Aufbau", "Deload", "Repertoire".
class Phase {
  const Phase({
    required this.id,
    required this.name,
    required this.weeks,
    required this.schedule,
    this.description,
    this.goal,
  });

  final String id;
  final String name;

  /// Länge in Wochen. Eine Woche hat [Schedule.cycleLength] Tage.
  final int weeks;

  final Schedule schedule;
  final String? description;

  /// Woran man merkt, dass die Phase sitzt — der Übergangs-Check.
  final String? goal;

  int get totalDays => weeks * schedule.cycleLength;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'weeks': weeks,
        'schedule': schedule.toJson(),
        if (description != null) 'description': description,
        if (goal != null) 'goal': goal,
      };

  static Phase fromJson(Map<String, dynamic> json) => Phase(
        id: json['id'] as String,
        name: json['name'] as String,
        weeks: (json['weeks'] as num).round(),
        schedule: Schedule.fromJson(json['schedule'] as Map<String, dynamic>),
        description: json['description'] as String?,
        goal: json['goal'] as String?,
      );
}

/// Das Programm: eine Folge von Phasen.
class Program {
  const Program({
    required this.id,
    required this.name,
    this.description,
    this.domain = 'allgemein',
    this.author,
    this.tags = const [],
    this.phases = const [],
    this.rationale,
  });

  final String id;
  final String name;
  final String? description;
  final String domain;
  final String? author;
  final List<String> tags;
  final List<Phase> phases;

  /// Warum der Plan so aussieht, wie er aussieht. Bei AI-generierten
  /// Programmen die Begründung — der Teil, der aus "Übungsliste" eine
  /// nachvollziehbare Diagnose macht.
  final String? rationale;

  int get totalWeeks => phases.fold(0, (sum, p) => sum + p.weeks);

  int get totalDays => phases.fold(0, (sum, p) => sum + p.totalDays);

  Set<String> get routineIds =>
      phases.expand((p) => p.schedule.routineIds).toSet();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (description != null) 'description': description,
        'domain': domain,
        if (author != null) 'author': author,
        if (tags.isNotEmpty) 'tags': tags,
        'phases': phases.map((e) => e.toJson()).toList(),
        if (rationale != null) 'rationale': rationale,
      };

  static Program fromJson(Map<String, dynamic> json) => Program(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        domain: json['domain'] as String? ?? 'allgemein',
        author: json['author'] as String?,
        tags: (json['tags'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(growable: false),
        phases: (json['phases'] as List<dynamic>? ?? const [])
            .map((e) => Phase.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        rationale: json['rationale'] as String?,
      );
}
