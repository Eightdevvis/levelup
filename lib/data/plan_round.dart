import 'dart:convert';

import '../model/library.dart';
import '../model/program.dart';
import '../model/set_spec.dart';
import '../model/target.dart';
import 'tag_round.dart';

/// Runde 2 des kostenlosen Weges: aus Übungen wird ein Programm.
///
/// Die Übungen stehen zu diesem Zeitpunkt schon fest — aufgelöst gegen die
/// Bibliothek oder frisch geschrieben. Die KI ordnet sie nur noch: zu
/// Einheiten, zu Tagen, zu Phasen. Sie bekommt deshalb Kennungen zu sehen und
/// gibt Kennungen zurück; die Übungstexte reisen nicht ein zweites Mal durch
/// den Chat, wo sie sich unbemerkt ändern könnten.

class PlanParseResult {
  const PlanParseResult({this.bundle, this.error, this.warnings = const []});

  final Bundle? bundle;
  final String? error;

  /// Was übergangen wurde, ohne dass der Import daran scheitert — eine
  /// unbekannte Übungskennung etwa. Sichtbar, aber kein Abbruch: ein Plan mit
  /// neun statt zehn Übungen ist brauchbar, eine Fehlermeldung nicht.
  final List<String> warnings;

  bool get ok => bundle != null;
}

/// Baut aus der zweiten KI-Antwort ein Bundle.
///
/// [exercises] sind die aufgelösten Übungen aus Runde 1 — nur auf sie darf
/// sich der Plan beziehen.
PlanParseResult parseRoundTwo(String raw, List<Resolved> exercises) {
  final text = stripFences(raw);
  if (text.trim().isEmpty) {
    return const PlanParseResult(error: 'Nichts eingefügt.');
  }

  final Map<String, dynamic> root;
  try {
    final decoded = jsonDecode(_onlyObject(text));
    if (decoded is! Map<String, dynamic>) {
      return const PlanParseResult(error: 'Erwartet wird ein JSON-Objekt.');
    }
    root = decoded;
  } on FormatException catch (e) {
    return PlanParseResult(error: 'Ungültiges JSON: ${e.message}');
  }

  final programJson = root['program'];
  if (programJson is! Map<String, dynamic>) {
    return const PlanParseResult(error: 'Es fehlt das Feld "program".');
  }

  final warnings = <String>[];
  final byId = {for (final r in exercises) r.exercise.id: r.exercise};

  // --- Einheiten ------------------------------------------------------------
  final routines = <String, Routine>{};
  for (final roh in _list(root['units'])) {
    if (roh is! Map<String, dynamic>) continue;
    final id = _text(roh['id']);
    if (id == null) {
      warnings.add('Eine Einheit ohne "id" wurde übergangen.');
      continue;
    }

    final slots = <ExerciseSlot>[];
    for (final rohSlot in _list(roh['exercises'])) {
      if (rohSlot is! Map<String, dynamic>) continue;
      final exerciseId = _text(rohSlot['id']);
      if (exerciseId == null || !byId.containsKey(exerciseId)) {
        warnings.add(
          'Einheit "$id" verweist auf die unbekannte Übung '
          '"${exerciseId ?? '?'}" — übergangen.',
        );
        continue;
      }
      slots.add(
        ExerciseSlot(
          exerciseId: exerciseId,
          sets: [_setSpec(rohSlot)],
          note: _text(rohSlot['note']),
        ),
      );
    }

    if (slots.isEmpty) {
      warnings.add('Einheit "$id" hat keine gültige Übung — übergangen.');
      continue;
    }
    routines[id] = Routine(
      id: id,
      name: _text(roh['name']) ?? 'Einheit $id',
      description: _text(roh['description']),
      slots: slots,
    );
  }

  if (routines.isEmpty) {
    return PlanParseResult(
      error: 'Keine einzige gültige Einheit im Plan.',
      warnings: warnings,
    );
  }

  // --- Phasen ---------------------------------------------------------------
  final programTags = [
    for (final t in _list(programJson['tags']))
      if (_text(t) != null) normalizeTag(_text(t)!),
  ].where((t) => t.isNotEmpty).toList();

  final programId = slugFor(
    programTags.isEmpty ? '' : programTags.first,
    _text(programJson['name']) ?? 'programm',
  );

  final phases = <Phase>[];
  final phasenJson = _list(programJson['phases']);
  for (var i = 0; i < phasenJson.length; i++) {
    final roh = phasenJson[i];
    if (roh is! Map<String, dynamic>) continue;

    final days = <DaySlot>[];
    for (final tag in _list(roh['days'])) {
      final name = _text(tag);
      if (name == null) continue;
      if (routines.containsKey(name)) {
        days.add(DaySlot(routineId: name));
        continue;
      }
      // Alles, was keine Einheit ist, ist ein freier Tag. Die KI schreibt da
      // „pause", „rest", „frei" oder auch mal „—"; das auseinanderzuhalten
      // wäre Aufwand ohne Ertrag.
      days.add(DaySlot.rest(name.length <= 12 ? name : 'Pause'));
    }

    if (days.isEmpty) {
      warnings.add('Phase ${i + 1} hat keine Tage — übergangen.');
      continue;
    }

    phases.add(
      Phase(
        id: '$programId-p${i + 1}',
        name: _text(roh['name']) ?? 'Phase ${i + 1}',
        weeks: _int(roh['weeks']) ?? 1,
        schedule: CycleSchedule(days: days),
        description: _text(roh['description']),
        goal: _text(roh['goal']),
      ),
    );
  }

  if (phases.isEmpty) {
    return PlanParseResult(
      error: 'Der Plan hat keine einzige Phase mit Tagen.',
      warnings: warnings,
    );
  }

  // Nur die Übungen mitgeben, die auch vorkommen — sonst wandert alles aus
  // dem Chat in die Bibliothek, auch was der Plan verworfen hat.
  final benutzt = <String>{
    for (final phase in phases)
      for (final routineId in phase.schedule.routineIds)
        ...?routines[routineId]?.slots.map((s) => s.exerciseId),
  };

  final program = Program(
    id: programId,
    name: _text(programJson['name']) ?? 'Programm',
    description: _text(programJson['description']),
    // Die Tätigkeit steht als erster Tag — genau wie bei der Übung. Was die
    // KI angegeben hat, kommt nach vorn, der Rest sind die Tags der Übungen.
    tags: {
      ...programTags,
      for (final id in benutzt) ...?byId[id]?.tags,
    }.toList(),
    phases: phases,
    rationale: _text(programJson['rationale']),
  );

  return PlanParseResult(
    bundle: Bundle(
      exercises: [for (final id in benutzt) byId[id]!],
      routines: {
        for (final phase in phases)
          for (final routineId in phase.schedule.routineIds)
            if (routines[routineId] != null) routines[routineId]!,
      }.toList(),
      programs: [program],
    ),
    warnings: warnings,
  );
}

/// Minuten, Wiederholungen oder gar nichts.
///
/// Zeit passt für Instrumente und Gehör, Wiederholungen fürs Krafttraining.
/// Beides zuzulassen kostet ein `if` und erspart dem Nutzer, „3 Sätze à 12"
/// als „5 Minuten" zu lesen.
SetSpec _setSpec(Map<String, dynamic> roh) {
  final minutes = _int(roh['minutes']);
  if (minutes != null && minutes > 0) {
    return SetSpec(target: DurationTarget(seconds: minutes * 60));
  }
  final reps = _int(roh['reps']);
  if (reps != null && reps > 0) {
    return SetSpec(target: RepsTarget(reps: reps));
  }
  final seconds = _int(roh['seconds']);
  if (seconds != null && seconds > 0) {
    return SetSpec(target: DurationTarget(seconds: seconds));
  }
  return const SetSpec(target: OpenTarget());
}

/// Schneidet das äußerste JSON-Objekt heraus.
String _onlyObject(String text) {
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start == -1 || end <= start) return text;
  return text.substring(start, end + 1);
}

List<dynamic> _list(dynamic value) => value is List ? value : const [];

String? _text(dynamic value) {
  if (value is! String) return null;
  final clean = value.trim();
  return clean.isEmpty ? null : clean;
}

int? _int(dynamic value) => value is num ? value.round() : null;
