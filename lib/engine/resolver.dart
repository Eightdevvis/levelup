import '../model/exercise.dart';
import '../model/library.dart';
import '../model/program.dart';
import '../model/set_spec.dart';
import '../model/target.dart';

/// Wo im Programm man gerade steht.
class DayRef {
  const DayRef({
    required this.globalDay,
    required this.phaseIndex,
    required this.weekInPhase,
    required this.dayInCycle,
  });

  /// 0-basierter Tag über das gesamte Programm.
  final int globalDay;

  final int phaseIndex;

  /// 0-basierte Woche innerhalb der Phase — der Wert, an dem Progression hängt.
  final int weekInPhase;

  /// 0-basierter Tag innerhalb des Zyklus.
  final int dayInCycle;

  @override
  bool operator ==(Object other) =>
      other is DayRef &&
      other.globalDay == globalDay &&
      other.phaseIndex == phaseIndex &&
      other.weekInPhase == weekInPhase &&
      other.dayInCycle == dayInCycle;

  @override
  int get hashCode => Object.hash(globalDay, phaseIndex, weekInPhase, dayInCycle);
}

/// Eine Übung, fertig aufgelöst für einen konkreten Tag: Übungsobjekt plus
/// die Sätze, wie sie in dieser Woche gelten.
class ResolvedItem {
  const ResolvedItem({
    required this.slot,
    required this.exercise,
    required this.sets,
  });

  final ExerciseSlot slot;
  final Exercise exercise;

  /// Bereits durch die Progression gelaufen.
  final List<SetSpec> sets;

  bool get isMissing => exercise.name == 'Unbekannte Übung';

  /// Grobe Zeitschätzung; nur Dauer-Ziele und Pausen sind wirklich messbar.
  int get estimatedSeconds {
    var total = 0;
    for (final set in sets) {
      final target = set.target;
      if (target is DurationTarget) total += target.seconds;
      total += slot.restSeconds;
    }
    return total;
  }
}

/// Ein Tag, fertig zum Abspielen.
class ResolvedDay {
  const ResolvedDay({
    required this.ref,
    required this.phase,
    required this.items,
    this.routine,
    this.label,
  });

  final DayRef ref;
  final Phase phase;
  final Routine? routine;
  final List<ResolvedItem> items;
  final String? label;

  bool get isRest => routine == null;

  String get title => routine?.name ?? label ?? 'Pause';

  /// Nur die Pflicht-Übungen zählen für "Tag geschafft".
  int get requiredCount => items.where((i) => !i.slot.optional).length;

  int get estimatedSeconds =>
      items.fold(0, (sum, item) => sum + item.estimatedSeconds);

  /// "Phase 2 · Woche 3 · Tag 1"
  String get positionLabel =>
      'Woche ${ref.weekInPhase + 1} · Tag ${ref.dayInCycle + 1}';
}

/// Rechnet Programm-Struktur in konkrete Tage um.
///
/// Hier laufen die drei Ebenen zusammen: die Phase bestimmt den Schedule,
/// die Woche bestimmt die Progression, der Tag bestimmt die Liste.
class ProgramResolver {
  const ProgramResolver(this.library);

  final Library library;

  /// Übersetzt einen fortlaufenden Tag in seine Position im Programm.
  /// Gibt `null` zurück, wenn das Programm zu Ende ist.
  DayRef? dayRefFor(Program program, int globalDay) {
    if (globalDay < 0) return null;

    var remaining = globalDay;
    for (var phaseIndex = 0; phaseIndex < program.phases.length; phaseIndex++) {
      final phase = program.phases[phaseIndex];
      final phaseDays = phase.totalDays;
      if (phaseDays <= 0) continue;

      if (remaining < phaseDays) {
        final cycle = phase.schedule.cycleLength;
        return DayRef(
          globalDay: globalDay,
          phaseIndex: phaseIndex,
          weekInPhase: remaining ~/ cycle,
          dayInCycle: remaining % cycle,
        );
      }
      remaining -= phaseDays;
    }
    return null;
  }

  /// Der vollständig aufgelöste Tag inklusive progressionsbereinigter Sätze.
  ResolvedDay? resolveDay(Program program, int globalDay) {
    final ref = dayRefFor(program, globalDay);
    if (ref == null) return null;
    return resolveRef(program, ref);
  }

  ResolvedDay? resolveRef(Program program, DayRef ref) {
    if (ref.phaseIndex >= program.phases.length) return null;
    final phase = program.phases[ref.phaseIndex];
    final daySlot = phase.schedule.slotForDay(ref.dayInCycle);

    if (daySlot.isRest) {
      return ResolvedDay(
        ref: ref,
        phase: phase,
        items: const [],
        label: daySlot.label ?? 'Pause',
      );
    }

    final routine = library.routine(daySlot.routineId!);
    if (routine == null) {
      return ResolvedDay(
        ref: ref,
        phase: phase,
        items: const [],
        label: 'Liste "${daySlot.routineId}" fehlt',
      );
    }

    final items = routine.slots
        .map((slot) => ResolvedItem(
              slot: slot,
              exercise: library.exercise(slot.exerciseId),
              sets: slot.setsForWeek(ref.weekInPhase),
            ))
        .toList(growable: false);

    return ResolvedDay(
      ref: ref,
      phase: phase,
      routine: routine,
      items: items,
      label: daySlot.label,
    );
  }

  /// Alle Tage einer Phase — für die Programm-Übersicht.
  List<ResolvedDay> resolvePhase(Program program, int phaseIndex) {
    if (phaseIndex >= program.phases.length) return const [];

    var offset = 0;
    for (var i = 0; i < phaseIndex; i++) {
      offset += program.phases[i].totalDays;
    }

    final phase = program.phases[phaseIndex];
    final days = <ResolvedDay>[];
    for (var day = 0; day < phase.totalDays; day++) {
      final resolved = resolveDay(program, offset + day);
      if (resolved != null) days.add(resolved);
    }
    return days;
  }

  /// Die Tage einer einzelnen Woche — die Ansicht, in der man tatsächlich lebt.
  List<ResolvedDay> resolveWeek(
    Program program,
    int phaseIndex,
    int weekInPhase,
  ) {
    if (phaseIndex >= program.phases.length) return const [];
    final phase = program.phases[phaseIndex];
    final cycle = phase.schedule.cycleLength;

    var offset = 0;
    for (var i = 0; i < phaseIndex; i++) {
      offset += program.phases[i].totalDays;
    }
    offset += weekInPhase * cycle;

    final days = <ResolvedDay>[];
    for (var day = 0; day < cycle; day++) {
      final resolved = resolveDay(program, offset + day);
      if (resolved != null) days.add(resolved);
    }
    return days;
  }

  /// Erster Tag der Phase, als globaler Index.
  int phaseStartDay(Program program, int phaseIndex) {
    var offset = 0;
    for (var i = 0; i < phaseIndex && i < program.phases.length; i++) {
      offset += program.phases[i].totalDays;
    }
    return offset;
  }
}
