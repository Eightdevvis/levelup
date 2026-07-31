/// Ergebnis eines einzelnen Satzes.
class SetLog {
  const SetLog({
    required this.setIndex,
    this.done = false,
    this.achieved,
    this.note,
  });

  final int setIndex;
  final bool done;

  /// Was tatsächlich erreicht wurde: 14 statt 12 Wiederholungen, 17 von 20
  /// Intervallen richtig. Null, wenn nur abgehakt wurde.
  final num? achieved;

  final String? note;

  SetLog copyWith({bool? done, num? achieved, String? note}) => SetLog(
    setIndex: setIndex,
    done: done ?? this.done,
    achieved: achieved ?? this.achieved,
    note: note ?? this.note,
  );

  Map<String, dynamic> toJson() => {
    'setIndex': setIndex,
    'done': done,
    if (achieved != null) 'achieved': achieved,
    if (note != null) 'note': note,
  };

  static SetLog fromJson(Map<String, dynamic> json) => SetLog(
    setIndex: (json['setIndex'] as num).round(),
    done: json['done'] as bool? ?? false,
    achieved: json['achieved'] as num?,
    note: json['note'] as String?,
  );
}

/// Ergebnis einer Übung an einem Tag.
class ItemLog {
  const ItemLog({
    required this.exerciseId,
    this.sets = const [],
    this.skipped = false,
  });

  final String exerciseId;
  final List<SetLog> sets;
  final bool skipped;

  bool get isComplete =>
      skipped || (sets.isNotEmpty && sets.every((s) => s.done));

  ItemLog copyWith({List<SetLog>? sets, bool? skipped}) => ItemLog(
    exerciseId: exerciseId,
    sets: sets ?? this.sets,
    skipped: skipped ?? this.skipped,
  );

  Map<String, dynamic> toJson() => {
    'exerciseId': exerciseId,
    'sets': sets.map((e) => e.toJson()).toList(),
    if (skipped) 'skipped': true,
  };

  static ItemLog fromJson(Map<String, dynamic> json) => ItemLog(
    exerciseId: json['exerciseId'] as String,
    sets: (json['sets'] as List<dynamic>? ?? const [])
        .map((e) => SetLog.fromJson(e as Map<String, dynamic>))
        .toList(growable: false),
    skipped: json['skipped'] as bool? ?? false,
  );
}

/// Was an einem Tag passiert ist.
class SessionLog {
  const SessionLog({
    required this.programId,
    required this.globalDay,
    required this.startedAt,
    this.completedAt,
    this.items = const [],
    this.note,
  });

  final String programId;
  final int globalDay;
  final DateTime startedAt;
  final DateTime? completedAt;
  final List<ItemLog> items;
  final String? note;

  bool get isComplete => completedAt != null;

  SessionLog copyWith({
    DateTime? completedAt,
    List<ItemLog>? items,
    String? note,
  }) => SessionLog(
    programId: programId,
    globalDay: globalDay,
    startedAt: startedAt,
    completedAt: completedAt ?? this.completedAt,
    items: items ?? this.items,
    note: note ?? this.note,
  );

  Map<String, dynamic> toJson() => {
    'programId': programId,
    'globalDay': globalDay,
    'startedAt': startedAt.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    'items': items.map((e) => e.toJson()).toList(),
    if (note != null) 'note': note,
  };

  static SessionLog fromJson(Map<String, dynamic> json) => SessionLog(
    programId: json['programId'] as String,
    globalDay: (json['globalDay'] as num).round(),
    startedAt: DateTime.parse(json['startedAt'] as String),
    completedAt: json['completedAt'] == null
        ? null
        : DateTime.parse(json['completedAt'] as String),
    items: (json['items'] as List<dynamic>? ?? const [])
        .map((e) => ItemLog.fromJson(e as Map<String, dynamic>))
        .toList(growable: false),
    note: json['note'] as String?,
  );
}

/// Wo man in einem Programm steht.
///
/// Bewusst an Programm-Tagen statt an Kalendertagen aufgehängt: wer zwei Tage
/// aussetzt, verliert nicht den Plan, sondern macht da weiter, wo er war.
class ProgramProgress {
  const ProgramProgress({
    required this.programId,
    required this.startedAt,
    this.currentDay = 0,
    this.completedDays = const {},
  });

  final String programId;
  final DateTime startedAt;
  final int currentDay;
  final Set<int> completedDays;

  bool isDayComplete(int globalDay) => completedDays.contains(globalDay);

  ProgramProgress copyWith({int? currentDay, Set<int>? completedDays}) =>
      ProgramProgress(
        programId: programId,
        startedAt: startedAt,
        currentDay: currentDay ?? this.currentDay,
        completedDays: completedDays ?? this.completedDays,
      );

  ProgramProgress markComplete(int globalDay) => copyWith(
    completedDays: {...completedDays, globalDay},
    currentDay: globalDay >= currentDay ? globalDay + 1 : currentDay,
  );

  Map<String, dynamic> toJson() => {
    'programId': programId,
    'startedAt': startedAt.toIso8601String(),
    'currentDay': currentDay,
    'completedDays': completedDays.toList()..sort(),
  };

  static ProgramProgress fromJson(Map<String, dynamic> json) => ProgramProgress(
    programId: json['programId'] as String,
    startedAt: DateTime.parse(json['startedAt'] as String),
    currentDay: (json['currentDay'] as num?)?.round() ?? 0,
    completedDays: (json['completedDays'] as List<dynamic>? ?? const [])
        .map((e) => (e as num).round())
        .toSet(),
  );
}
