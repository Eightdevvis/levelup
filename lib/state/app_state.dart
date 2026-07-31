import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/seed.dart';
import '../data/storage.dart';
import '../engine/resolver.dart';
import '../model/library.dart';
import '../model/program.dart';
import '../model/session.dart';

/// Ergebnis eines Import-Versuchs — bewusst als Wert statt als Exception,
/// weil ein AI-generiertes Bundle regelmäßig teilweise kaputt ist und der
/// Nutzer sehen soll, *was* fehlt.
class ImportResult {
  const ImportResult({
    required this.ok,
    this.message = '',
    this.warnings = const [],
    this.importedPrograms = const [],
  });

  final bool ok;
  final String message;
  final List<String> warnings;
  final List<Program> importedPrograms;
}

/// Zentraler Zustand. Bewusst ein einzelner ChangeNotifier statt einer
/// State-Management-Bibliothek — die App hat einen Datenstamm, nicht zehn.
class AppState extends ChangeNotifier {
  AppState(this._store);

  final Store _store;

  AppSnapshot _snapshot = const AppSnapshot();
  bool _loading = true;

  bool get isLoading => _loading;
  Library get library => _snapshot.library;
  Map<String, ProgramProgress> get progressByProgram => _snapshot.progress;
  List<SessionLog> get sessions => _snapshot.sessions;

  ProgramResolver get resolver => ProgramResolver(library);

  List<Program> get programs {
    final list = library.programs.values.toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Future<void> init() async {
    final loaded = await _store.load();
    if (loaded == null || loaded.library.isEmpty) {
      _snapshot = AppSnapshot(library: const Library().merge(seedBundle()));
      await _persist();
    } else {
      _snapshot = loaded;
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> _persist() => _store.save(_snapshot);

  // -- Fortschritt ---------------------------------------------------------

  ProgramProgress progressFor(String programId) =>
      _snapshot.progress[programId] ??
      ProgramProgress(programId: programId, startedAt: DateTime.now());

  bool hasStarted(String programId) =>
      _snapshot.progress.containsKey(programId);

  Future<void> startProgram(String programId) async {
    if (_snapshot.progress.containsKey(programId)) return;
    _snapshot = _snapshot.copyWith(
      progress: {
        ..._snapshot.progress,
        programId: ProgramProgress(
          programId: programId,
          startedAt: DateTime.now(),
        ),
      },
    );
    notifyListeners();
    await _persist();
  }

  Future<void> setCurrentDay(String programId, int globalDay) async {
    final current = progressFor(programId);
    _snapshot = _snapshot.copyWith(
      progress: {
        ..._snapshot.progress,
        programId: current.copyWith(currentDay: globalDay),
      },
    );
    notifyListeners();
    await _persist();
  }

  /// Tag abschließen und den Verlauf schreiben.
  Future<void> completeDay(
    String programId,
    int globalDay, {
    List<ItemLog> items = const [],
  }) async {
    final current = progressFor(programId);
    final updated = current.markComplete(globalDay);

    final log = SessionLog(
      programId: programId,
      globalDay: globalDay,
      startedAt: DateTime.now(),
      completedAt: DateTime.now(),
      items: items,
    );

    // Ein erneuter Durchlauf desselben Tages ersetzt den alten Eintrag,
    // statt den Verlauf mit Dubletten zu füllen.
    final sessions =
        _snapshot.sessions
            .where(
              (s) => !(s.programId == programId && s.globalDay == globalDay),
            )
            .toList()
          ..add(log);

    _snapshot = _snapshot.copyWith(
      progress: {..._snapshot.progress, programId: updated},
      sessions: sessions,
    );
    notifyListeners();
    await _persist();
  }

  Future<void> resetProgram(String programId) async {
    final progress = {..._snapshot.progress}..remove(programId);
    _snapshot = _snapshot.copyWith(
      progress: progress,
      sessions: _snapshot.sessions
          .where((s) => s.programId != programId)
          .toList(),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> deleteProgram(String programId) async {
    final progress = {..._snapshot.progress}..remove(programId);
    _snapshot = _snapshot.copyWith(
      library: _snapshot.library.withoutProgram(programId),
      progress: progress,
      sessions: _snapshot.sessions
          .where((s) => s.programId != programId)
          .toList(),
    );
    notifyListeners();
    await _persist();
  }

  // -- Import / Export -----------------------------------------------------

  /// Nimmt das JSON, das eine AI ausgibt, und legt es in die Bibliothek.
  Future<ImportResult> importJson(String raw) async {
    final text = _stripCodeFence(raw);
    if (text.isEmpty) {
      return const ImportResult(ok: false, message: 'Nichts zum Importieren.');
    }

    Bundle bundle;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        return const ImportResult(
          ok: false,
          message: 'Erwartet wird ein JSON-Objekt mit "programs".',
        );
      }
      bundle = Bundle.fromJson(decoded);
    } on FormatException catch (e) {
      return ImportResult(ok: false, message: 'Ungültiges JSON: ${e.message}');
    } catch (e) {
      return ImportResult(ok: false, message: 'Import fehlgeschlagen: $e');
    }

    if (bundle.isEmpty) {
      return const ImportResult(
        ok: false,
        message: 'Bundle enthält weder Übungen noch Listen noch Programme.',
      );
    }

    final merged = _snapshot.library.merge(bundle);

    // Nach dem Zusammenführen prüfen, nicht davor: eine Übung darf auch aus
    // der bestehenden Bibliothek kommen, statt im Bundle mitgeliefert zu sein.
    final warnings = <String>[];
    for (final program in bundle.programs) {
      warnings.addAll(merged.missingReferences(program.id));
    }

    _snapshot = _snapshot.copyWith(library: merged);
    notifyListeners();
    await _persist();

    final count = bundle.programs.length;
    return ImportResult(
      ok: true,
      message: count == 1
          ? '"${bundle.programs.first.name}" importiert.'
          : '$count Programme importiert.',
      warnings: warnings,
      importedPrograms: bundle.programs,
    );
  }

  String exportProgram(String programId) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(library.bundleForProgram(programId).toJson());
  }

  /// Entfernt ```json-Zäune, die beim Kopieren aus einem Chat mitkommen.
  static String _stripCodeFence(String raw) {
    var text = raw.trim();
    if (!text.startsWith('```')) return text;

    final firstBreak = text.indexOf('\n');
    if (firstBreak == -1) return '';
    text = text.substring(firstBreak + 1);

    final closing = text.lastIndexOf('```');
    if (closing != -1) text = text.substring(0, closing);
    return text.trim();
  }
}
